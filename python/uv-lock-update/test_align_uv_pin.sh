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

# The production invocation runs with cwd inside a workspace whose pin may
# reject the runner's uv; --no-config is what keeps the aligner alive there.
run_align_in_pinned_dir() {
  local pin="$1"
  mkdir -p "$TMPDIR/pinned"
  printf '[tool.uv]\nrequired-version = "%s"\n' "$pin" > "$TMPDIR/pinned/pyproject.toml"
  : > "$TMPDIR/github_output"
  set +e
  OUT=$(cd "$TMPDIR/pinned" && GITHUB_OUTPUT="$TMPDIR/github_output" \
    uv run --no-project --no-config --python '>=3.11' --with packaging \
    python "$SCRIPT" "$TMPDIR/pyproject.toml" 0.13.7 2> "$TMPDIR/err.log")
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
check "old specifier is reported" \
  "==0.12.12" "$(read_output "$TMPDIR/github_output" old_pin)"
check "new specifier is reported" \
  ">=0.13.7,<0.14" "$(read_output "$TMPDIR/github_output" new_pin)"
check "pin rewritten in place" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"
check "comment above the pin survives" "1" "$(grep -c "$OLD_LINE" "$TMPDIR/pyproject.toml" || true)"
check "sibling keys survive" \
  'exclude-newer = "7 days"' \
  "$(grep '^exclude-newer' "$TMPDIR/pyproject.toml" || true)"

# A pin that already accepts Dependabot's uv is left strictly alone.
write_pyproject '==0.13.7'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "satisfied exact pin untouched" "0" "$STATUS"
check "satisfied exact pin reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"
check "satisfied exact pin reports compatibility, so UV_BIN stays usable" \
  "true" "$(read_output "$TMPDIR/github_output" compatible)"
check "satisfied exact pin prints nothing to output old_pin" \
  "" "$(read_output "$TMPDIR/github_output" old_pin || true)"
check "satisfied exact pin file unchanged" \
  'required-version = "==0.13.7"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

write_pyproject '>=0.12'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "satisfied floor pin untouched" "0" "$STATUS"
check "satisfied floor pin reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"

write_pyproject '>=0.13,<0.14'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "satisfied range pin untouched" "0" "$STATUS"

# A compatible-release pin whose window excludes Dependabot's uv is rewritten.
write_pyproject '~=0.12.12'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "unsatisfied compatible-release pin rewritten" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# An unsatisfied compound range is replaced wholesale.
write_pyproject '>=0.12,<0.13'
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "unsatisfied compound range rewritten" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# Single-quoted TOML strings rewrite too.
cat > "$TMPDIR/pyproject.toml" <<'EOF'
[tool.uv]
required-version = '==0.12.12'
EOF
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "single-quoted pin rewritten" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# The lower bound is Dependabot's uv and patch releases are included.
write_pyproject '>=0.13.7,<0.14'
run_align "$TMPDIR/pyproject.toml" 0.13.8
check "patch bump inside the window untouched" "0" "$STATUS"
check "patch bump reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"

write_pyproject '>=0.13.7,<0.14'
run_align "$TMPDIR/pyproject.toml" 0.14.0
check "minor bump rewritten" \
  'required-version = ">=0.14.0,<0.15"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# Next-minor math carries the ones digit: 0.9.x rewinds to <0.10.
write_pyproject '==0.9.3'
run_align "$TMPDIR/pyproject.toml" 0.9.3
check "matching minor stays untouched" "0" "$STATUS"
write_pyproject '==0.9.3'
run_align "$TMPDIR/pyproject.toml" 0.9.4
check "patch above an exact pin rewrites to the next minor" \
  'required-version = ">=0.9.4,<0.10"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# No pin to align is a notice, not an error.
run_align "$TMPDIR/absent.toml" 0.13.7
check "missing pyproject.toml exits cleanly" "0" "$STATUS"
check "missing pyproject.toml reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"
check "missing pyproject.toml reports incompatibility, so UV_BIN is dropped" \
  "false" "$(read_output "$TMPDIR/github_output" compatible)"
check "missing pyproject.toml emits a notice" \
  "1" "$(grep -c '::notice::' "$TMPDIR/out.log" || true)"

printf '[project]\nname = "demo"\n' > "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "missing [tool.uv] exits cleanly" "0" "$STATUS"
check "missing [tool.uv] reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"

printf '[tool.uv]\nexclude-newer = "7 days"\n' > "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "missing required-version exits cleanly" "0" "$STATUS"
check "missing required-version reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"

# Bad inputs fail the run loudly.
printf '[tool.uv]\nrequired-version = "banana"\n' > "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "unparseable pin fails" "2" "$STATUS"

printf '[tool.uv]\nrequired-version = "==0.12.12"\n' > "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" banana
check "non-version argument fails" "2" "$STATUS"

write_pyproject '==0.12.12'
run_align "$TMPDIR/pyproject.toml" 1
check "one-component version fails cleanly" "2" "$STATUS"

run_align
check "usage error exits 2" "2" "$STATUS"

# Regression: uv enforces required-version even under --no-project, so the
# invocation needs --no-config to survive a cwd pin rejecting the runner's uv.
write_pyproject '==0.12.12'
run_align_in_pinned_dir '==0.0.1'
check "aligner survives a cwd pin that rejects the runner uv" "0" "$STATUS"
check "pinned-cwd run rewrote the target pin" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# A dotted key is valid TOML uv accepts, but no line rewrite can reach it.
printf 'tool.uv.required-version = "==0.12.12"\n' > "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "dotted key exits cleanly" "0" "$STATUS"
check "dotted key reports no alignment" \
  "false" "$(read_output "$TMPDIR/github_output" aligned)"
check "dotted key reports incompatibility, so UV_BIN is dropped" \
  "false" "$(read_output "$TMPDIR/github_output" compatible)"
check "dotted key emits a warning" \
  "1" "$(grep -c '::warning::' "$TMPDIR/out.log" || true)"
check "dotted key leaves the file untouched" \
  'tool.uv.required-version = "==0.12.12"' \
  "$(grep 'required-version' "$TMPDIR/pyproject.toml")"

# A CRLF pyproject.toml keeps its line endings.
cat > "$TMPDIR/pyproject.toml" <<'EOF'
[tool.uv]
required-version = "==0.12.12"
exclude-newer = "7 days"
EOF
sed -i 's/$/\r/' "$TMPDIR/pyproject.toml"
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "CRLF file rewritten correctly" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(tr -d '\r' < "$TMPDIR/pyproject.toml" | grep '^required-version')"
check "CRLF endings survive the rewrite" \
  "3" "$(grep -c $'\r' "$TMPDIR/pyproject.toml" || true)"

# A trailing comment on the pin line survives the rewrite.
cat > "$TMPDIR/pyproject.toml" <<'EOF'
[tool.uv]
required-version = "==0.12.12"  # bump manually when a newer uv is needed
EOF
run_align "$TMPDIR/pyproject.toml" 0.13.7
check "rewritten pin keeps its trailing comment" \
  'required-version = ">=0.13.7,<0.14"  # bump manually when a newer uv is needed' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# The check accepts a prerelease Dependabot uv (prereleases=True).
write_pyproject '==0.13.7'
run_align "$TMPDIR/pyproject.toml" 0.13.8rc1
check "prerelease Dependabot uv rewrites the pin" \
  'required-version = ">=0.13.8rc1,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"

# Without GITHUB_OUTPUT (manual debugging), the script still works.
write_pyproject '==0.12.12'
set +e
OUT=$(uv run --no-project --no-config --python '>=3.11' --with packaging \
  python "$SCRIPT" "$TMPDIR/pyproject.toml" 0.13.7 2> /dev/null)
STATUS=$?
set -e
check "no-output-file mode succeeds" "0" "$STATUS"
check "no-output-file mode rewrote the pin" \
  'required-version = ">=0.13.7,<0.14"' \
  "$(grep '^required-version' "$TMPDIR/pyproject.toml")"
check "no-output-file mode reports the rewrite" \
  "1" "$(grep -c '^Aligned required-version' <<< "$OUT" || true)"

exit $FAIL
