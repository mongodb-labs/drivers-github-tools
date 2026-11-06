#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/install_uv.sh"
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

# A release tarball shaped like uv's: one top directory carrying the binary.
STAGE="$TMPDIR/stage/uv-0.13.7"
mkdir -p "$STAGE"
cat > "$STAGE/uv" <<'EOF'
#!/usr/bin/env bash
echo "uv 0.13.7-test"
EOF
chmod +x "$STAGE/uv"
TARBALL="$TMPDIR/uv.tar.gz"
tar -czf "$TARBALL" -C "$TMPDIR/stage" uv-0.13.7

# curl serves the tarball and fails on demand; uname is stubbed per platform.
BIN="$TMPDIR/bin"
mkdir -p "$BIN"
CALLS="$TMPDIR/calls.log"
cat > "$BIN/curl" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
[ -n "\${CURL_FAIL:-}" ] && exit 22
# Honor -o like real curl; stdout stays clean for the log assertions.
out=""
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "-o" ]; then out="\$arg"; break; fi
  prev="\$arg"
done
cat "\${CURL_TARBALL:-$TARBALL}" > "\$out"
STUB
chmod +x "$BIN/curl"
cat > "$BIN/uname" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -s) echo "${UNAME_S:-Linux}" ;;
  -m) echo "${UNAME_M:-x86_64}" ;;
  *) echo "unexpected uname invocation: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$BIN/uname"

run_install() {
  : > "$CALLS"
  : > "$TMPDIR/output"
  rm -rf "$TMPDIR/runner-temp"
  set +e
  OUT=$(PATH="$BIN:$PATH" DEPENDABOT_UV="${DEPENDABOT_UV:-0.13.7}" \
    CURL_FAIL="${CURL_FAIL:-}" \
    UNAME_S="${UNAME_S:-Linux}" UNAME_M="${UNAME_M:-x86_64}" \
    RUNNER_TEMP="$TMPDIR/runner-temp" GITHUB_OUTPUT="$TMPDIR/output" \
    bash "$SCRIPT" 2> "$TMPDIR/err.log")
  STATUS=$?
  set -e
  printf '%s\n' "$OUT" > "$TMPDIR/out.log"
}

# Linux x86_64: the runner case.
run_install
check "install succeeds" "0" "$STATUS"
check "downloads the linux x86_64 tarball and reports the binary" \
  "1 uv 0.13.7-test" \
  "$(grep -c 'https://github.com/astral-sh/uv/releases/download/0.13.7/uv-x86_64-unknown-linux-gnu.tar.gz' "$CALLS" || true) $OUT"
check "writes the binary path for later steps" \
  "$TMPDIR/runner-temp/dependabot-uv-0.13.7/uv" \
  "$(read_output "$TMPDIR/output" uv_bin)"

# A failed download warns and exits 0: the lock update keeps shipping.
CURL_FAIL=1 run_install
check "download failure warns instead of failing" \
  "0 1" "$STATUS $(grep -c '::warning::' "$TMPDIR/out.log" || true)"
check "download failure writes no uv_bin" "" "$(read_output "$TMPDIR/output" uv_bin || true)"

# An unsupported platform is the same degradation.
UNAME_M=riscv64 run_install
check "unsupported platform warns instead of failing" \
  "0 1" "$STATUS $(grep -c '::warning::' "$TMPDIR/out.log" || true)"
check "unsupported platform writes no uv_bin" "" "$(read_output "$TMPDIR/output" uv_bin || true)"

exit $FAIL
