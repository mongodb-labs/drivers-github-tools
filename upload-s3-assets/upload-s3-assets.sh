#!/usr/bin/env bash
# Upload the files of the S3 assets directory to the release bucket.
# Environment: VERSION and PRODUCT_NAME (required), FILENAMES, DRY_RUN.
set -eu

FILENAMES="${FILENAMES:-*}"
DRY_RUN="${DRY_RUN:-false}"

cd "${S3_ASSETS}"
if [ "${DRY_RUN}" == "false" ]; then
  for filename in ${FILENAMES}; do
    aws s3 cp "${filename}" "s3://${AWS_BUCKET}/${PRODUCT_NAME}/${VERSION}/${filename}"
  done
else
  for filename in ${FILENAMES}; do
    echo "Would upload ${filename} to ${PRODUCT_NAME}/${VERSION}/${filename}"
  done
  echo "Dry run, skipping S3 Upload of ${FILENAMES}" >> "$GITHUB_STEP_SUMMARY"
fi
