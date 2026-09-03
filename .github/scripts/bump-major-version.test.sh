#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP_MAJOR_SH="$SCRIPT_DIR/bump-major-version.sh"
FAILURES=0

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $description (expected '$expected', got '$actual')" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: $description"
  fi
}

# Test: writes the major version number to the given file
tmp_file=$(mktemp)
bash "$BUMP_MAJOR_SH" "4.0.0" "$tmp_file"
assert_eq "writes major version" "4" "$(cat "$tmp_file")"
rm -f "$tmp_file"

# Test: multi-digit major version
tmp_file=$(mktemp)
bash "$BUMP_MAJOR_SH" "12.3.4" "$tmp_file"
assert_eq "writes multi-digit major version" "12" "$(cat "$tmp_file")"
rm -f "$tmp_file"

# Test: missing version argument fails
if bash "$BUMP_MAJOR_SH" >/dev/null 2>&1; then
  echo "FAIL: expected failure with no version argument" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: fails with no version argument"
fi

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES test(s) failed" >&2
  exit 1
fi

echo "All bump-major-version.sh tests passed"
