#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/autoupdate.sh"
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

check_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected to find: $needle"
    echo "  in: $haystack"
    FAIL=1
  fi
}

check_absent() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "FAIL: $desc"
    echo "  expected not to find: $needle"
    FAIL=1
  else
    echo "OK: $desc"
  fi
}

# autoupdate.sh reaches apply_cooldown.py and diff_config.py through
# $ACTION_PATH, so pointing that at stubs isolates its own orchestration from
# the real cooldown and the real diff.
STUB="$TMPDIR/action"
mkdir -p "$STUB"
cat > "$STUB/apply_cooldown.py" <<'STUB_EOF'
import os
import shutil
import sys

old, new, cooldown = sys.argv[1:4]
with open(os.environ["STUB_ARGS_LOG"], "w") as handle:
    handle.write(cooldown + "\n")
# Stand in for a cooldown that reverted every proposed update.
if os.environ.get("STUB_REVERT") == "true":
    shutil.copyfile(old, new)
held = os.environ.get("STUB_HELD", "")
if held:
    print(held)
STUB_EOF
cat > "$STUB/diff_config.py" <<'STUB_EOF'
import os

updates = os.environ.get("STUB_UPDATES", "- demo: `1.0` -> `2.0`")
if updates:
    print(updates)
STUB_EOF

# A repo whose config differs from HEAD, so the "no changes" early exit is not
# taken and the script runs its full body.
REPO="$TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf 'old\n' > "$REPO/.pre-commit-config.yaml"
git -C "$REPO" add .pre-commit-config.yaml
git -C "$REPO" commit -qm init

# Read a step output back out of a $GITHUB_OUTPUT file, resolving the heredoc
# form autoupdate.sh writes multi-line values with. Parsing it the way Actions
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

# Every variable autoupdate.sh documents as required on the dry-run path.
# GH_TOKEN, GITHUB_REPOSITORY, and BRANCH are deliberately absent: they are
# referenced only by the commit and push, which a dry run skips.
run_autoupdate() {
  local skip="${1:-}"
  : > "$TMPDIR/github_output"
  : > "$TMPDIR/stub_args"
  printf 'new\n' > "$REPO/.pre-commit-config.yaml"
  printf 'old\n' > "$TMPDIR/config.before"
  (
    cd "$REPO" || exit 1
    export DRY_RUN=true
    export OLD_CONFIG="$TMPDIR/config.before"
    export CONFIG_PATH=".pre-commit-config.yaml"
    export COOLDOWN_DAYS=7
    export ACTION_PATH="$STUB"
    export GITHUB_OUTPUT="$TMPDIR/github_output"
    export STUB_ARGS_LOG="$TMPDIR/stub_args"
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
run_autoupdate
STATUS=$?
set -e

check "dry run succeeds" "0" "$STATUS"
check "a change is reported, so the pull request step runs" \
  "true" "$(read_output "$TMPDIR/github_output" changed)"
check "body starts with the summary heading" \
  "## Updated hooks" \
  "$(read_output "$TMPDIR/github_output" body | head -1)"
check_contains "body carries the diff output" \
  '- demo: `1.0` -> `2.0`' \
  "$(read_output "$TMPDIR/github_output" body)"
check "the configured cooldown reaches apply_cooldown.py" \
  "7" "$(cat "$TMPDIR/stub_args")"

check "dry run creates no commit" "1" "$(git -C "$REPO" rev-list --count HEAD)"
check "dry run leaves the branch alone" \
  "" \
  "$(git -C "$REPO" branch --list pre-commit-autoupdate)"

# Nothing was held, so the body must not carry an empty section implying
# something was.
check_absent "no held section when nothing was held" \
  "Held back by the cooldown" \
  "$(read_output "$TMPDIR/github_output" body)"

# What the cooldown held belongs in the body: it tells a reviewer the run was
# not simply quiet, and names what to expect next week.
set +e
STUB_HELD='- demo: held `3.0`, released 1d ago (cooldown 7d)' run_autoupdate
set -e
check_contains "a held update is reported under its own heading" \
  "## Held back by the cooldown" \
  "$(read_output "$TMPDIR/github_output" body)"
check_contains "a held update is listed" \
  'held `3.0`' \
  "$(read_output "$TMPDIR/github_output" body)"
check_contains "a held update does not displace the updated hooks section" \
  "## Updated hooks" \
  "$(read_output "$TMPDIR/github_output" body)"

# The cooldown can revert every proposed update, leaving the config exactly as
# it started. Opening a pull request then would produce an empty diff.
set +e
STUB_REVERT=true STUB_HELD='- demo: held `3.0`' run_autoupdate
set -e
check "a fully reverted update gates the pull request step off" \
  "false" "$(read_output "$TMPDIR/github_output" changed)"
check_contains "a fully reverted update says why it stopped" \
  "Every update was held back by the cooldown" \
  "$(cat "$TMPDIR/out.log")"
check "a fully reverted update emits no body" \
  "" "$(read_output "$TMPDIR/github_output" body)"

# Change detection compares against the pre-update copy, not against HEAD. A
# workspace that was already dirty must still count as "no change" when the
# update produced nothing.
: > "$TMPDIR/nochange_output"
printf 'new\n' > "$REPO/.pre-commit-config.yaml"
printf 'new\n' > "$TMPDIR/config.unchanged"
set +e
(
  cd "$REPO" || exit 1
  export DRY_RUN=true COOLDOWN_DAYS=7 ACTION_PATH="$STUB"
  export OLD_CONFIG="$TMPDIR/config.unchanged" CONFIG_PATH=".pre-commit-config.yaml"
  export GITHUB_OUTPUT="$TMPDIR/nochange_output" STUB_ARGS_LOG="$TMPDIR/stub_args"
  bash "$SCRIPT"
) > "$TMPDIR/nochange.log" 2>&1
STATUS=$?
set -e

check "dirty workspace with an unchanged config exits cleanly" "0" "$STATUS"
check "dirty workspace with an unchanged config reports no changes" \
  "No changes detected, skipping PR creation" \
  "$(cat "$TMPDIR/nochange.log")"
check "no changes gates the pull request step off" \
  "false" "$(read_output "$TMPDIR/nochange_output" changed)"
check "no changes emits no body" \
  "" "$(read_output "$TMPDIR/nochange_output" body)"

# Each documented variable is genuinely required: unset it and the script fails
# rather than proceeding with an empty value.
for VAR in DRY_RUN OLD_CONFIG CONFIG_PATH COOLDOWN_DAYS ACTION_PATH GITHUB_OUTPUT; do
  set +e
  run_autoupdate "$VAR"
  STATUS=$?
  set -e
  check "missing $VAR fails the run" "1" "$([ "$STATUS" -ne 0 ] && echo 1 || echo 0)"
done

exit $FAIL
