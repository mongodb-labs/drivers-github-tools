#!/usr/bin/env bash
set -euo pipefail

BUMP="${1:?Usage: next-version.sh <patch|minor|major>}"

case "$BUMP" in
  patch|minor|major) ;;
  *)
    echo "Unknown bump type: $BUMP" >&2
    exit 1
    ;;
esac

LATEST_SEMVER=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sed 's/^v//' \
  | sort -t. -k1,1n -k2,2n -k3,3n \
  | tail -1 || true)

if [ -n "$LATEST_SEMVER" ]; then
  MAJOR=$(echo "$LATEST_SEMVER" | cut -d. -f1)
  MINOR=$(echo "$LATEST_SEMVER" | cut -d. -f2)
  PATCH=$(echo "$LATEST_SEMVER" | cut -d. -f3)

  case "$BUMP" in
    major)
      MAJOR=$((MAJOR + 1))
      MINOR=0
      PATCH=0
      ;;
    minor)
      MINOR=$((MINOR + 1))
      PATCH=0
      ;;
    patch)
      PATCH=$((PATCH + 1))
      ;;
  esac
else
  LATEST_FLOATING=$(git tag -l 'v[0-9]*' \
    | grep -E '^v[0-9]+$' \
    | sed 's/^v//' \
    | sort -n \
    | tail -1 || true)

  if [ -z "$LATEST_FLOATING" ]; then
    echo "No version tags found (neither vX.Y.Z nor vN)." >&2
    exit 1
  fi

  echo "No vX.Y.Z tag found; bootstrapping from floating tag v${LATEST_FLOATING}. Ignoring requested bump '${BUMP}'." >&2
  MAJOR="$LATEST_FLOATING"
  MINOR=0
  PATCH=0
fi

NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"

if [ "$MAJOR" = "3" ]; then
  IS_V3=true
else
  IS_V3=false
fi

echo "NEXT_VERSION=${NEXT_VERSION}"
echo "IS_V3=${IS_V3}"
