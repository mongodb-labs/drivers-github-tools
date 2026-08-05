#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/decide_pr_action.sh"
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

FAKE_GH="$TMPDIR/gh"
cat > "$FAKE_GH" <<FAKE_GH_EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMPDIR/gh_calls.log"
if [ "\$1" = "pr" ] && [ "\$2" = "list" ]; then
  # Apply the caller's own --jq against the canned response, so the real filter
  # is exercised rather than a copy of it that could drift.
  JQ_EXPR='.[0].number // empty'
  while [ \$# -gt 0 ]; do
    if [ "\$1" = "--jq" ]; then JQ_EXPR="\$2"; fi
    shift
  done
  jq -r "\$JQ_EXPR" "$TMPDIR/pr_list_response.json"
fi
FAKE_GH_EOF
chmod +x "$FAKE_GH"
export PATH="$TMPDIR:$PATH"

# A non-default base throughout, so a hardcoded "main" cannot pass.
run_script() {
  local pr_list_json="$1"
  local dry_run="$2"
  echo "$pr_list_json" > "$TMPDIR/pr_list_response.json"
  : > "$TMPDIR/gh_calls.log"
  BRANCH="uv-lock-update" \
  BASE="v4.16" \
  TITLE="Automation: Update uv.lock" \
  BODY="## Updated packages" \
  LABELS="dependencies" \
  DRY_RUN="$dry_run" \
    bash "$SCRIPT" > "$TMPDIR/output.log" 2>&1 || true
}

gh_call() { grep "^pr $1" "$TMPDIR/gh_calls.log" || true; }
mutating_calls() { grep -E '^pr (create|edit)' "$TMPDIR/gh_calls.log" || true; }

# No open PR: create one targeting BASE. The lookup must not filter on base, or
# a PR a reviewer retargeted is missed and a second PR opens on the branch.
run_script '[]' "false"
check "no open PR: list finds the branch by head and state alone" \
  "pr list --head uv-lock-update --state open --json number,isCrossRepository --jq map(select(.isCrossRepository == false)) | .[0].number // empty" \
  "$(gh_call list)"
check "no open PR: a PR is created against the configured base" \
  "pr create --title Automation: Update uv.lock --body ## Updated packages --base v4.16 --label dependencies --head uv-lock-update" \
  "$(gh_call create)"
check "no open PR: nothing is edited" "" "$(gh_call edit)"

# A fork can open a pull request whose head branch has the same name, and gh
# cannot filter that out for us. Editing it would rewrite a stranger's pull
# request, so it must be ignored and a fresh one created instead.
run_script '[{"number": 99, "isCrossRepository": true}]' "false"
check "fork PR on the same branch name is ignored" "" "$(gh_call edit)"
check "fork PR on the same branch name: ours is created instead" \
  "pr create --title Automation: Update uv.lock --body ## Updated packages --base v4.16 --label dependencies --head uv-lock-update" \
  "$(gh_call create)"

# Open PR found by head branch even though its base differs from BASE: it is
# refreshed in place rather than duplicated.
run_script '[{"number": 42, "isCrossRepository": false}]' "false"
check "open PR: it is edited in place with the new body and label" \
  "pr edit 42 --body ## Updated packages --add-label dependencies" \
  "$(gh_call edit)"
check "open PR: no second PR is created" "" "$(gh_call create)"

# `gh pr create --dry-run` documents that it "may still push git changes", so a
# dry run must report the decision without reaching any mutating gh command.
run_script '[{"number": 42, "isCrossRepository": false}]' "true"
check "open PR + dry run: no mutating gh call" "" "$(mutating_calls)"
check_contains "open PR + dry run: output names the PR it would update" \
  "Would update PR #42" "$(cat "$TMPDIR/output.log")"
# The body appears nowhere else in the dry-run output, so finding it proves the
# generated summary was logged and not just the create-or-update decision.
check_contains "open PR + dry run: the body is logged" \
  "## Updated packages" "$(cat "$TMPDIR/output.log")"

run_script '[]' "true"
check "no open PR + dry run: no mutating gh call" "" "$(mutating_calls)"
check_contains "no open PR + dry run: output names the branch and base" \
  "from uv-lock-update into v4.16" "$(cat "$TMPDIR/output.log")"
check_contains "no open PR + dry run: the body is logged" \
  "## Updated packages" "$(cat "$TMPDIR/output.log")"

exit $FAIL
