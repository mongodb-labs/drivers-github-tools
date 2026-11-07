#!/usr/bin/env bash
# Print the uv version Dependabot's latest updater image ships, parsed from
# dependabot-core's uv/Dockerfile (DRIVERS-3711). Exit 4 when undeterminable.
set -euo pipefail

TAGS_URL="https://api.github.com/repos/dependabot/dependabot-core/tags?per_page=1"
CORE_RAW="https://raw.githubusercontent.com/dependabot/dependabot-core"

die() {
  echo "dependabot_uv.sh: $1" >&2
  exit 4
}

# Updater images build from release tags; the rate-limited API falls back to main.
ref=main
auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GH_TOKEN")
fi
# ${auth[@]+...}: an empty array trips set -u on bash < 4.4.
if tags_json=$(curl -fsS --connect-timeout 10 --max-time 30 \
    ${auth[@]+"${auth[@]}"} "$TAGS_URL"); then
  parsed=$(printf '%s' "$tags_json" | jq -r '.[0]?.name // empty' 2>/dev/null || true)
  if [ -n "$parsed" ]; then
    ref=$parsed
  fi
fi

# The Dockerfile installs uv from the version-tagged official image; match
# the line exactly, so an upstream refactor reads as undeterminable, not wrong.
dockerfile=$(curl -fsS --connect-timeout 10 --max-time 30 \
  "$CORE_RAW/$ref/uv/Dockerfile") ||
  die "could not fetch $CORE_RAW/$ref/uv/Dockerfile"
matches=$(printf '%s\n' "$dockerfile" |
  sed -nE 's/^FROM ghcr\.io\/astral-sh\/uv:([0-9]+\.[0-9]+\.[0-9]+) AS uv$/\1/p')
[ "$(printf '%s' "$matches" | grep -c .)" = 1 ] ||
  die "no unambiguous 'FROM ghcr.io/astral-sh/uv:<version> AS uv' line in $CORE_RAW/$ref/uv/Dockerfile"
echo "$matches"
