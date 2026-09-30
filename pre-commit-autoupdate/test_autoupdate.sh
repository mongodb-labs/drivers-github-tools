#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/autoupdate.sh"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1" expected="$2" actual="$3"
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
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected to find: $needle"
    echo "  in: $haystack"
    FAIL=1
  fi
}

# Stub git so a push is recorded rather than attempted.
STUB="$TMPDIR/bin"
mkdir -p "$STUB"
cat > "$STUB/git" <<STUB_EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMPDIR/git_calls.log"
STUB_EOF
chmod +x "$STUB/git"
export PATH="$STUB:$PATH"

run_autoupdate() {
  : > "$TMPDIR/git_calls.log"
  : > "$TMPDIR/output"
  (
    export OLD_CONFIG="$TMPDIR/before.yaml"
    export CONFIG_PATH="$TMPDIR/after.yaml"
    export GITHUB_OUTPUT="$TMPDIR/output"
    export GITHUB_REPOSITORY="mongodb/example"
    export GH_TOKEN="fake-token"
    export BRANCH="pre-commit-autoupdate"
    export DRY_RUN="${DRY_RUN:-false}"
    bash "$SCRIPT" > "$TMPDIR/log" 2>&1
  ) || true
}

outputs() { cat "$TMPDIR/output"; }
log() { cat "$TMPDIR/log"; }
pushes() { grep -c -- "push --force" "$TMPDIR/git_calls.log" || true; }

BEFORE='repos:
  - repo: https://github.com/psf/black
    rev: 24.1.0'
AFTER='repos:
  - repo: https://github.com/psf/black
    rev: 24.2.0'

# An unchanged config must not open a pull request.
echo "$BEFORE" > "$TMPDIR/before.yaml"
echo "$BEFORE" > "$TMPDIR/after.yaml"
run_autoupdate
check "unchanged: changed=false" "changed=false" "$(outputs)"
check "unchanged: nothing is pushed" "0" "$(pushes)"

# A changed config is committed, pushed, and summarized for the PR body.
echo "$BEFORE" > "$TMPDIR/before.yaml"
echo "$AFTER" > "$TMPDIR/after.yaml"
run_autoupdate
check_contains "changed: changed=true" "changed=true" "$(outputs)"
check_contains "changed: the new rev is in the body" '- `24.2.0`' "$(outputs)"
check "changed: the branch is pushed once" "1" "$(pushes)"

# A dry run reports its decision without touching git.
DRY_RUN=true run_autoupdate
check_contains "dry run: changed=true" "changed=true" "$(outputs)"
check "dry run: nothing is pushed" "0" "$(pushes)"

exit $FAIL
