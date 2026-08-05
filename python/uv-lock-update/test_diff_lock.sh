#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/diff_lock.py"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Invoke diff_lock.py exactly as update_lock.sh does, so the interpreter under
# test is the one production uses rather than whatever python3 is on PATH.
run_diff() {
  uv run --no-project --python '>=3.11' python "$SCRIPT" "$@"
}

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

# One realistic uv.lock pair covering every case at once. Real locks open with a
# version preamble and an [options] table, and uv writes one [[package]] entry
# per resolution fork, so a package can appear more than once.
#   pymongo  root project entry uv writes with no version key
#   black    single locked version changed
#   cffi     gains a second forked version
#   click    added
#   urllib3  removed
#   flake8   unchanged
#   sphinx   one of two forked versions changed
#   anyio    two forked versions unchanged, written in a different entry order
cat > "$TMPDIR/old.lock" <<'EOF'
version = 1
revision = 3
requires-python = ">=3.10"

[options]
exclude-newer = "0001-01-01T00:00:00Z"
[[package]]
name = "pymongo"
source = { editable = "." }
[[package]]
name = "black"
version = "23.1.0"
[[package]]
name = "cffi"
version = "1.17.1"
[[package]]
name = "urllib3"
version = "2.0.0"
[[package]]
name = "flake8"
version = "6.0.0"
[[package]]
name = "sphinx"
version = "7.4.7"
[[package]]
name = "sphinx"
version = "8.1.3"
[[package]]
name = "anyio"
version = "4.11.0"
[[package]]
name = "anyio"
version = "4.5.2"
EOF

cat > "$TMPDIR/new.lock" <<'EOF'
version = 1
revision = 3
requires-python = ">=3.10"

[options]
exclude-newer = "0001-01-01T00:00:00Z"
[[package]]
name = "pymongo"
source = { editable = "." }
[[package]]
name = "black"
version = "23.3.0"
[[package]]
name = "cffi"
version = "1.17.1"
[[package]]
name = "cffi"
version = "2.0.0"
[[package]]
name = "click"
version = "8.1.0"
[[package]]
name = "flake8"
version = "6.0.0"
[[package]]
name = "sphinx"
version = "7.4.7"
[[package]]
name = "sphinx"
version = "8.2.0"
[[package]]
name = "anyio"
version = "4.5.2"
[[package]]
name = "anyio"
version = "4.11.0"
EOF

# Capture stdout only. uv writes progress to stderr on a cold cache, which would
# otherwise contaminate the assertions below. $STATUS still catches a crash.
set +e
ACTUAL=$(run_diff "$TMPDIR/old.lock" "$TMPDIR/new.lock")
STATUS=$?
set -e

check "version-less root entry does not crash the diff" "0" "$STATUS"

check "changed version" \
  "- black: \`23.1.0\` → \`23.3.0\`" \
  "$(echo "$ACTUAL" | grep '^- black:' || true)"

check "package gains a forked version" \
  "- cffi: \`1.17.1\` → \`1.17.1\`, \`2.0.0\`" \
  "$(echo "$ACTUAL" | grep '^- cffi:' || true)"

check "added package" \
  "- click: added \`8.1.0\`" \
  "$(echo "$ACTUAL" | grep '^- click:' || true)"

check "removed package" \
  "- urllib3: removed \`2.0.0\`" \
  "$(echo "$ACTUAL" | grep '^- urllib3:' || true)"

check "one of several forked versions changed" \
  "- sphinx: \`7.4.7\`, \`8.1.3\` → \`7.4.7\`, \`8.2.0\`" \
  "$(echo "$ACTUAL" | grep '^- sphinx:' || true)"

check "unchanged package omitted" \
  "" \
  "$(echo "$ACTUAL" | grep '^- flake8:' || true)"

check "unchanged forked versions omitted whatever the entry order" \
  "" \
  "$(echo "$ACTUAL" | grep '^- anyio:' || true)"

check "version-less root project is not reported" \
  "" \
  "$(echo "$ACTUAL" | grep 'pymongo' || true)"

check "only the changed packages are reported" \
  "5" \
  "$(echo "$ACTUAL" | grep -c '^-' || true)"

REVERSED=$(run_diff "$TMPDIR/new.lock" "$TMPDIR/old.lock")
check "package loses a forked version" \
  "- cffi: \`1.17.1\`, \`2.0.0\` → \`1.17.1\`" \
  "$(echo "$REVERSED" | grep '^- cffi:' || true)"

check "identical inputs produce empty output" \
  "" \
  "$(run_diff "$TMPDIR/new.lock" "$TMPDIR/new.lock")"

exit $FAIL
