#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/dependabot_uv.sh"
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

# Stub curl: dispatch on URL, serve fixtures, fail on demand, log every call.
BIN="$TMPDIR/bin"
mkdir -p "$BIN"
FIXTURES="$TMPDIR/fixtures"
mkdir -p "$FIXTURES"
CALLS="$TMPDIR/calls.log"

cat > "$BIN/curl" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
case "\$*" in
  *"api.github.com/repos/dependabot/dependabot-core/tags"*)
    [ -n "\${TAGS_FAIL:-}" ] && exit 22
    cat "\${TAGS_FIXTURE:-$FIXTURES/tags.json}" ;;
  *"dependabot-core/"*"/uv/Dockerfile"*)
    cat "\${DOCKERFILE_FIXTURE:-$FIXTURES/Dockerfile}" ;;
  *)
    echo "unexpected curl invocation: \$*" >&2
    exit 1 ;;
esac
STUB
chmod +x "$BIN/curl"

# The tags API response dependabot-core serves: tag objects, newest first.
cat > "$FIXTURES/tags.json" <<'EOF'
[
  {
    "name": "v0.403.0",
    "zipball_url": "https://api.github.com/repos/dependabot/dependabot-core/zipball/refs/tags/v0.403.0",
    "tarball_url": "https://api.github.com/repos/dependabot/dependabot-core/tarball/refs/tags/v0.403.0",
    "commit": {"sha": "9ac98a409855e01424e00469efb87377a173334d", "url": "https://api.github.com/repos/dependabot/dependabot-core/commits/9ac98a409855e01424e00469efb87377a173334d"},
    "node_id": "MDM6UmVmOTMxNjMwNzM6cmVmc90tagsvMC40MDMuMA=="
  }
]
EOF

# Excerpt of dependabot-core's uv/Dockerfile, decoy FROM lines included.
cat > "$FIXTURES/Dockerfile" <<'EOF'
# syntax=docker.io/docker/dockerfile:1.20
ARG PY_3_15=3.15.2
ARG PYENV_VERSION=v2.6.16

FROM ghcr.io/astral-sh/uv:0.13.7 AS uv

FROM ghcr.io/dependabot/dependabot-updater-core AS python-core

USER dependabot
RUN git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch $PYENV_VERSION --single-branch --depth=1 /usr/local/.pyenv

# Install uv by copying from the official image
COPY --from=uv /uv /uvx /usr/local/bin/
COPY --chown=dependabot:dependabot --parents cargo common $DEPENDABOT_HOME/
EOF

# A Dockerfile without the uv line must read as undeterminable, not garbage.
cat > "$FIXTURES/Dockerfile-nouvx" <<'EOF'
FROM ghcr.io/dependabot/dependabot-updater-core AS python-core
COPY --from=uv /uv /uvx /usr/local/bin/
EOF

run_dependabot_uv() {
  : > "$CALLS"
  set +e
  OUT=$(PATH="$BIN:$PATH" TAGS_FAIL="${TAGS_FAIL:-}" \
    TAGS_FIXTURE="${TAGS_FIXTURE:-}" DOCKERFILE_FIXTURE="${DOCKERFILE_FIXTURE:-}" \
    GH_TOKEN="${GH_TOKEN:-}" \
    bash "$SCRIPT" 2> "$TMPDIR/err.log")
  STATUS=$?
  set -e
}

# Happy path: newest tag, its Dockerfile, the uv version it ships.
run_dependabot_uv
check "prints the uv version from the latest tagged Dockerfile" "0.13.7" "$OUT"
check "succeeds" "0" "$STATUS"
check "fetches the Dockerfile at the resolved tag, not main" \
  "1" \
  "$(grep -c 'https://raw.githubusercontent.com/dependabot/dependabot-core/v0.403.0/uv/Dockerfile' "$CALLS" || true)"

# An unanswerable tags call falls back to main rather than skipping tracking.
TAGS_FAIL=1 run_dependabot_uv
check "tags API failure falls back to main" "0.13.7" "$OUT"
check "fallback fetches the Dockerfile from main" \
  "1" \
  "$(grep -c 'https://raw.githubusercontent.com/dependabot/dependabot-core/main/uv/Dockerfile' "$CALLS" || true)"

# Undeterminable version: exit 4, nothing on stdout, reason on stderr.
DOCKERFILE_FIXTURE="$FIXTURES/Dockerfile-nouvx" run_dependabot_uv
check "Dockerfile without a uv FROM line exits 4" "4" "$STATUS"
check "Dockerfile without a uv FROM line prints no version" "" "$OUT"

exit $FAIL
