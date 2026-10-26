#!/usr/bin/env bash
# Generate the report for authorized publication on distribution channels.
# Environment: PRODUCT_NAME, RELEASE_VERSION, FILENAMES, ACTOR, RUN_ID, TOKEN.
set -eu

if [ -n "${TOKEN:-}" ]; then
  export GH_TOKEN="${TOKEN}"
fi
NAME=$(gh api "users/${ACTOR}" --jq '.name')
REPORT=$S3_ASSETS/authorized-publication.txt
FILENAMES="${FILENAMES:-}"
cat << EOT > $REPORT
Product: ${PRODUCT_NAME}
Version: ${RELEASE_VERSION}
Releaser: $NAME
Build Source: GitHub Actions
Build Number: ${RUN_ID}
EOT
if [ -z "$FILENAMES" ]; then
  echo "No published artifacts." >> $REPORT
else
  for filename in $FILENAMES; do
    SHA=$(shasum -a 256 $filename | awk '{print $1;}')
    echo "Filename: $filename"  >> $REPORT
    echo "Shasum: $SHA"  >> $REPORT
  done
fi
