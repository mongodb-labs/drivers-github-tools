#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXT_VERSION_SH="$SCRIPT_DIR/next-version.sh"
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

new_temp_repo() {
  local tmp
  tmp=$(mktemp -d)
  git init -q "$tmp"
  git -C "$tmp" config user.email "test@example.com"
  git -C "$tmp" config user.name "Test"
  git -C "$tmp" commit -q --allow-empty -m "init"
  echo "$tmp"
}

# Test: no tags at all -> non-zero exit
repo=$(new_temp_repo)
if (cd "$repo" && bash "$NEXT_VERSION_SH" patch) >/dev/null 2>&1; then
  echo "FAIL: expected failure with no tags present" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: fails with no tags present"
fi
rm -rf "$repo"

# Test: bootstrap from floating v3 tag, ignoring the requested bump
repo=$(new_temp_repo)
git -C "$repo" tag v3
OUTPUT=$(cd "$repo" && bash "$NEXT_VERSION_SH" patch)
assert_eq "bootstrap ignores bump, uses floating major" "$(printf 'NEXT_VERSION=3.0.0\nIS_V3=true')" "$OUTPUT"
rm -rf "$repo"

# Test: patch bump from full semver tag
repo=$(new_temp_repo)
git -C "$repo" tag v3.2.1
OUTPUT=$(cd "$repo" && bash "$NEXT_VERSION_SH" patch)
assert_eq "patch bump" "$(printf 'NEXT_VERSION=3.2.2\nIS_V3=true')" "$OUTPUT"
rm -rf "$repo"

# Test: minor bump resets patch
repo=$(new_temp_repo)
git -C "$repo" tag v3.2.1
OUTPUT=$(cd "$repo" && bash "$NEXT_VERSION_SH" minor)
assert_eq "minor bump resets patch" "$(printf 'NEXT_VERSION=3.3.0\nIS_V3=true')" "$OUTPUT"
rm -rf "$repo"

# Test: major bump resets minor/patch and flips IS_V3 to false
repo=$(new_temp_repo)
git -C "$repo" tag v3.2.1
OUTPUT=$(cd "$repo" && bash "$NEXT_VERSION_SH" major)
assert_eq "major bump resets minor/patch" "$(printf 'NEXT_VERSION=4.0.0\nIS_V3=false')" "$OUTPUT"
rm -rf "$repo"

# Test: a full semver tag takes priority over an existing floating tag
repo=$(new_temp_repo)
git -C "$repo" tag v3
git -C "$repo" tag v3.2.1
OUTPUT=$(cd "$repo" && bash "$NEXT_VERSION_SH" patch)
assert_eq "full semver tag wins over floating tag" "$(printf 'NEXT_VERSION=3.2.2\nIS_V3=true')" "$OUTPUT"
rm -rf "$repo"

# Test: numeric sort, not lexicographic (v3.10.0 > v3.2.1)
repo=$(new_temp_repo)
git -C "$repo" tag v3.2.1
git -C "$repo" tag v3.10.0
OUTPUT=$(cd "$repo" && bash "$NEXT_VERSION_SH" patch)
assert_eq "numeric sort picks v3.10.0 over v3.2.1" "$(printf 'NEXT_VERSION=3.10.1\nIS_V3=true')" "$OUTPUT"
rm -rf "$repo"

# Test: invalid bump type is rejected
repo=$(new_temp_repo)
git -C "$repo" tag v3.2.1
if (cd "$repo" && bash "$NEXT_VERSION_SH" bogus) >/dev/null 2>&1; then
  echo "FAIL: expected failure for invalid bump type" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: rejects invalid bump type"
fi
rm -rf "$repo"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES test(s) failed" >&2
  exit 1
fi

echo "All next-version.sh tests passed"
