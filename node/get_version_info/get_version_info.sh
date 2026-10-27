#!/usr/bin/env bash
# Get the release version and the release package file name.
set -eu

package_version=$(jq --raw-output '.version' package.json)
echo "package_version=${package_version}" >> "$GITHUB_ENV"
npm pack
PACKFILE=$(ls ./*.tgz)
echo "package_file=$PACKFILE" >> "$GITHUB_ENV"
echo "commit=$(git rev-parse HEAD)" >> "$GITHUB_ENV"
