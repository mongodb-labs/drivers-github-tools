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

# update_lock.sh reaches diff_lock.py and decide_pr_action.sh through
# $ACTION_PATH, so pointing that at stubs isolates its own orchestration from
# the real diff and from any gh call.
STUB="$TMPDIR/action"
mkdir -p "$STUB"
printf 'print("- demo: `1.0` -> `2.0`")\n' > "$STUB/diff_lock.py"
cat > "$STUB/decide_pr_action.sh" <<STUB_EOF
#!/usr/bin/env bash
{
  echo "BRANCH=\$BRANCH"
  echo "BASE=\$BASE"
  echo "TITLE=\$TITLE"
  echo "LABELS=\$LABELS"
  echo "DRY_RUN=\$DRY_RUN"
  echo "BODY_FIRST_LINE=\$(echo "\$BODY" | head -1)"
  echo "BODY_LAST_LINE=\$(echo "\$BODY" | tail -1)"
} > "$TMPDIR/handoff.log"
STUB_EOF
chmod +x "$STUB/decide_pr_action.sh"

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

# Every variable update_lock.sh documents as required on the dry-run path.
# GH_TOKEN and GITHUB_REPOSITORY are deliberately absent: they are referenced
# only by the push, which a dry run skips.
run_update() {
  local skip="${1:-}"
  : > "$TMPDIR/handoff.log"
  (
    cd "$REPO" || exit 1
    export BRANCH=uv-lock-update
    export BASE=main
    export LABELS=dependencies
    export DRY_RUN=true
    export OLD_LOCK="$TMPDIR/uv.lock.before"
    export ACTION_PATH="$STUB"
    # Unset after exporting, so the variable is genuinely absent rather than
    # being reassigned by a later argument on the same command.
    if [ -n "$skip" ]; then
      unset "$skip"
    fi
    bash "$SCRIPT"
  ) > "$TMPDIR/out.log" 2>&1
}

# A dry run hands off the values the action promises, and leaves the repo alone.
set +e
run_update
STATUS=$?
set -e

check "dry run succeeds" "0" "$STATUS"
check "branch is handed off" "BRANCH=uv-lock-update" "$(grep '^BRANCH=' "$TMPDIR/handoff.log" || true)"
check "base is handed off" "BASE=main" "$(grep '^BASE=' "$TMPDIR/handoff.log" || true)"
check "labels are handed off" "LABELS=dependencies" "$(grep '^LABELS=' "$TMPDIR/handoff.log" || true)"
check "dry run flag is handed off" "DRY_RUN=true" "$(grep '^DRY_RUN=' "$TMPDIR/handoff.log" || true)"
check "title is supplied by update_lock.sh" \
  "TITLE=Automation: Update uv.lock" \
  "$(grep '^TITLE=' "$TMPDIR/handoff.log" || true)"
check "body starts with the summary heading" \
  "BODY_FIRST_LINE=## Updated packages" \
  "$(grep '^BODY_FIRST_LINE=' "$TMPDIR/handoff.log" || true)"
check "body carries the diff output" \
  'BODY_LAST_LINE=- demo: `1.0` -> `2.0`' \
  "$(grep '^BODY_LAST_LINE=' "$TMPDIR/handoff.log" || true)"

check "dry run creates no commit" "1" "$(git -C "$REPO" rev-list --count HEAD)"
check "dry run leaves the branch alone" \
  "" \
  "$(git -C "$REPO" branch --list uv-lock-update)"

# Each documented variable is genuinely required: unset it and the script fails
# rather than proceeding with an empty value.
# Change detection compares against the pre-upgrade copy, not against HEAD. A
# workspace that was already dirty must still count as "no change" when the
# upgrade produced nothing, or the pull request body would report no version
# changes while claiming there were some.
printf 'new\n' > "$TMPDIR/uv.lock.unchanged"
set +e
(
  cd "$REPO" || exit 1
  export BRANCH=uv-lock-update BASE=main LABELS=dependencies DRY_RUN=true
  export OLD_LOCK="$TMPDIR/uv.lock.unchanged" ACTION_PATH="$STUB"
  bash "$SCRIPT"
) > "$TMPDIR/nochange.log" 2>&1
STATUS=$?
set -e

check "dirty workspace with an unchanged lock exits cleanly" "0" "$STATUS"
check "dirty workspace with an unchanged lock reports no changes" \
  "No changes detected, skipping PR creation" \
  "$(cat "$TMPDIR/nochange.log")"

for VAR in BRANCH BASE LABELS DRY_RUN OLD_LOCK ACTION_PATH; do
  set +e
  run_update "$VAR"
  STATUS=$?
  set -e
  check "missing $VAR fails the run" "1" "$([ "$STATUS" -ne 0 ] && echo 1 || echo 0)"
done

exit $FAIL
