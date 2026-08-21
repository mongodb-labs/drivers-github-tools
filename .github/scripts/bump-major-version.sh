#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bump-major-version.sh <version> [version_file]}"
VERSION_FILE="${2:-.github/workflows/version.txt}"
MAJOR="${VERSION%%.*}"

echo "$MAJOR" > "$VERSION_FILE"
