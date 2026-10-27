#!/usr/bin/env bash
# Generate all the reports to be uploaded to the release bucket.
# Environment: PRODUCT_NAME and RELEASE_VERSION (required), SARIF_REPORT_TARGET_REF, SBOM_IN_PATH,
# KONDUKTO_SUB_PROJECT, SBOM_FILE_NAME, THIRD_PARTY_DEPENDENCY_TOOL, EVERGREEN_PROJECT,
# EVERGREEN_COMMIT, SECURITY_REPORT_LOCATION, DIST_FILENAMES, TOKEN, CODE_SCANNING_TOKEN.
set -eu

ROOT="$(dirname "${BASH_SOURCE[0]}")/.."
SBOM_IN_PATH="${SBOM_IN_PATH-sbom.json}"
SBOM_FILE_NAME="${SBOM_FILE_NAME:-cyclonedx.sbom.json}"
TOKEN="${TOKEN:-}"

echo "Generate Authorized Publication Report"
FILENAMES="${DIST_FILENAMES:-}" bash "${ROOT}/authorized-pub/authorized-pub.sh"

# Not all packages have third party dependencies, and so not all packages produce sboms.
if [ -n "${SBOM_IN_PATH}" ]; then
  echo "Generate SBOM File"
  SBOM_IN_PATH="${SBOM_IN_PATH}" SBOM_FILE_NAME="${SBOM_FILE_NAME}" \
    KONDUKTO_SUB_PROJECT="${KONDUKTO_SUB_PROJECT:-}" bash "${ROOT}/sbom/sbom.sh"
fi

echo "Generate Sarif File"
env "INPUT_REF=${SARIF_REPORT_TARGET_REF:-${RELEASE_VERSION}}" \
  "INPUT_OUTPUT-FILE=${S3_ASSETS}/code-scanning-alerts.json" \
  "INPUT_TOKEN=${CODE_SCANNING_TOKEN}" \
  node "${ROOT}/code-scanning-export/dist/index.js"

echo "Generate Compliance Report"
SBOM_NAME="${SBOM_FILE_NAME}" \
  SARIF_NAME=code-scanning-alerts.json \
  AUTHORIZED_PUB_NAME=authorized-publication.txt \
  SECURITY_REPORT_LOCATION="${SECURITY_REPORT_LOCATION:-}" \
  THIRD_PARTY_DEPENDENCY_TOOL="${THIRD_PARTY_DEPENDENCY_TOOL:-Kondukto}" \
  EVERGREEN_PROJECT="${EVERGREEN_PROJECT:-}" \
  EVERGREEN_COMMIT="${EVERGREEN_COMMIT:-}" \
  bash "${ROOT}/compliance-report/generate.sh"
