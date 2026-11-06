#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/align_uv_pin.py"
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

# Read a step output back out of a $GITHUB_OUTPUT file, the way Actions parses it.
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

# Invoke align_uv_pin.py exactly as the action does.
run_align() {
  : > "$TMPDIR/github_output"
  set +e
  OUT=$(GITHUB_OUTPUT="$TMPDIR/github_output" \
    uv run --no-project --no-config --python '>=3.11' --with packaging \
    python "$SCRIPT" "$@" 2> "$TMPDIR/err.log")
  STATUS=$?
  set -e
  printf '%s\n' "$OUT" > "$TMPDIR/out.log"
}

# A pyproject shaped like the Python driver's: commented pin, sibling keys.
write_pyproject() {
  cat > "$TMPDIR/pyproject.toml" <<EOF
[project]
name = "demo"

[tool.uv]
# Pin the uv binary version across local dev, GitHub Actions, and Evergreen.
required-version = "${1:-==0.12.12}"
exclude-newer = "7 days"
EOF
}

OLD_LINE='# Pin the uv binary version across local dev, GitHub Actions, and Evergreen.'

# An unsatisfied exact pin is rewritten in place.
write_pyproject '==0.12.12'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "unsatisfied exact pin succeeds" "0" "$STATUS"
check "rewrite is reported as aligned" \
  "true" "$(read_output "$TMPDIR/github_output" aligned)"
check "rewrite is reported as compatible" \
  "true" "$(read_output "$TMPDIR/github_output" compatible)"
check "old and new specifiers are reported" \
  "==0.12.12 >=0.13.7,<0.14" \
  "$(read_output "$TMPDIR/github_output" old_pin) $(read_output "$TMPDIR/github_output" new_pin)"
check "pin rewritten in place" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"
check "comment above the pin survives" "1" "$(grep -c "$OLD_LINE" "$TMPDIR/pyproject.toml" || true)"

# A pin that already accepts Dependabot's uv is left strictly alone.
write_pyproject '==0.13.7'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "satisfied pin untouched" "0" "$STATUS"
check "satisfied pin reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"
check "satisfied pin reports compatibility, so UV_BIN stays usable" \
  "true" "$(read_output "$TMPDIR/github_output" compatible)"

# A repository without a pin gets a notice and no other change.
run_align "$TMPDIR/absent.toml" 0.13.7
check "missing pyproject.toml exits cleanly" "0" "$STATUS"
check "missing pyproject.toml reports no alignment and incompatibility" \
  "false false" \
  "$(read_output "$TMPDIR/github_output" aligned) $(read_output "$TMPDIR/github_output" compatible)"
check "missing pyproject.toml emits a notice" \
  "1" "$(grep -c '::notice::' "$TMPDIR/out.log" || true)"

# A dotted key is valid TOML uv accepts, but no line rewrite can reach it:
# degrade to a warning and let the lock update continue with the uv on PATH.
printf 'tool.uv.required-version = "==0.12.12"\n' > "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "dotted key exits cleanly" "0" "$STATUS"
check "dotted key reports no alignment and incompatibility" \
  "false false" \
  "$(read_output "$TMPDIR/github_output" aligned) $(read_output "$TMPDIR/github_output" compatible)"
check "dotted key emits a warning" \
  "1" "$(grep -c '::warning::' "$TMPDIR/out.log" || true)"
check "dotted key leaves the file untouched" \
  'tool.uv.required-version = "==0.12.12"' \
  "$(grep 'required-version' "$TMPDIR/pyproject.toml")"

exit $FAIL
