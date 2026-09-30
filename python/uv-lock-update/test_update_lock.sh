#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/update_lock.sh"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=1
  fi
}

# update_lock.sh reaches diff_lock.py through $ACTION_PATH, so pointing that at a
# stub isolates its own orchestration from the real diff.
STUB="$TMPDIR/action"
mkdir -p "$STUB"
printf 'print("- demo: `1.0` -> `2.0`")\n' > "$STUB/diff_lock.py"

# A repo whose uv.lock differs from HEAD, so the "no changes" early exit is not
# taken and the script runs its full body.
REPO="$TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf 'old\n' > "$REPO/uv.lock"
git -C "$REPO" add uv.lock
git -C "$REPO" commit -qm init
printf 'new\n' > "$REPO/uv.lock"
printf 'old\n' > "$TMPDIR/uv.lock.before"

# Read a step output back out of a $GITHUB_OUTPUT file, resolving the heredoc
# form update_lock.sh writes multi-line values with. Parsing it the way Actions
# does is what proves the delimiter framing is well formed.
read_output() {
  local file="$1"
  local name="$2"
  awk -v key="$name" '
    !in_block && $0 ~ "^" key "<<" { delim = substr($0, length(key) + 3); in_block = 1; next }
    !in_block && index($0, key "=") == 1 { print substr($0, length(key) + 2); found = 1; next }
    in_block && $0 == delim { in_block = 0; next }
    in_block { print }
  ' "$file"
}

# Every variable update_lock.sh documents as required on the dry-run path.
# GH_TOKEN, GITHUB_REPOSITORY, and BRANCH are deliberately absent: they are
# referenced only by the commit and push, which a dry run skips.
run_update() {
  local skip="${1:-}"
  : > "$TMPDIR/github_output"
  (
    cd "$REPO" || exit 1
    export DRY_RUN=true
    export OLD_LOCK="$TMPDIR/uv.lock.before"
    export ACTION_PATH="$STUB"
    export GITHUB_OUTPUT="$TMPDIR/github_output"
    # Unset after exporting, so the variable is genuinely absent rather than
    # being reassigned by a later argument on the same command.
    if [ -n "$skip" ]; then
      unset "$skip"
    fi
    bash "$SCRIPT"
  ) > "$TMPDIR/out.log" 2>&1
}

# A dry run reports the values the action promises, and leaves the repo alone.
set +e
run_update
STATUS=$?
set -e

check "dry run succeeds" "0" "$STATUS"
check "a change is reported, so the pull request step runs" \
  "true" "$(read_output "$TMPDIR/github_output" changed)"
check "body starts with the summary heading" \
  "## Updated packages" \
  "$(read_output "$TMPDIR/github_output" body | head -1)"
check "body carries the diff output" \
  '- demo: `1.0` -> `2.0`' \
  "$(read_output "$TMPDIR/github_output" body | tail -1)"

check "dry run creates no commit" "1" "$(git -C "$REPO" rev-list --count HEAD)"
check "dry run leaves the branch alone" \
  "" \
  "$(git -C "$REPO" branch --list uv-lock-update)"

# Change detection compares against the pre-upgrade copy, not against HEAD. A
# workspace that was already dirty must still count as "no change" when the
# upgrade produced nothing, or the pull request body would report no version
# changes while claiming there were some.
printf 'new\n' > "$TMPDIR/uv.lock.unchanged"
: > "$TMPDIR/nochange_output"
set +e
(
  cd "$REPO" || exit 1
  export DRY_RUN=true
  export OLD_LOCK="$TMPDIR/uv.lock.unchanged" ACTION_PATH="$STUB"
  export GITHUB_OUTPUT="$TMPDIR/nochange_output"
  bash "$SCRIPT"
) > "$TMPDIR/nochange.log" 2>&1
STATUS=$?
set -e

check "dirty workspace with an unchanged lock exits cleanly" "0" "$STATUS"
check "dirty workspace with an unchanged lock reports no changes" \
  "No changes detected, skipping PR creation" \
  "$(cat "$TMPDIR/nochange.log")"
# The gate must be reported explicitly. An absent output would also skip the
# pull request step, but only because Actions treats it as empty, so asserting
# the literal value keeps that from passing by accident.
check "no changes gates the pull request step off" \
  "false" "$(read_output "$TMPDIR/nochange_output" changed)"
check "no changes emits no body" \
  "" "$(read_output "$TMPDIR/nochange_output" body)"

# Each documented variable is genuinely required: unset it and the script fails
# rather than proceeding with an empty value.
for VAR in DRY_RUN OLD_LOCK ACTION_PATH GITHUB_OUTPUT; do
  set +e
  run_update "$VAR"
  STATUS=$?
  set -e
  check "missing $VAR fails the run" "1" "$([ "$STATUS" -ne 0 ] && echo 1 || echo 0)"
done

exit $FAIL
