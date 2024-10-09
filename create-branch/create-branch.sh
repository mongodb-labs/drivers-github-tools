#! /bin/bash
set -eu

echo "Create or checkout the branch."
OWNER_REPO="${GITHUB_REPOSITORY}"
git ls-remote --exit-code --heads https://github.com/${OWNER_REPO}.git refs/heads/$BRANCH || {
  git branch $BRANCH $BASE_REF
}
git fetch origin $BRANCH || true
git checkout $BRANCH

echo "Get silk creds."
# shellcheck disable=SC2046
export $(grep -v '^#' $SILKBOMB_ENVFILE | xargs -0)

echo "Get a silk token."
SILK_JWT_TOKEN=$(curl -s -X POST "https://silkapi.us1.app.silk.security/api/v1/authenticate" \
  -H "accept: application/json" -H "Content-Type: application/json" \
  -d '{ "client_id": "'${SILK_CLIENT_ID}'", "client_secret": "'${SILK_CLIENT_SECRET}'" }' \
  | jq -r '.token')

echo "Get the silk asset group prefix."
if [ -z "${SILK_PREFIX:-}" ]; then
  REPO="${OWNER_REPO##*/}"
  SILK_PREFIX=${REPO}
fi
SILK_GROUP="${SILK_PREFIX}-${BRANCH}"

echo "Create the silk asset group."
json_payload=$(cat <<EOF
{
    "active": true,
    "name": "${SILK_GROUP}",
    "code_repo_url": "https://github.com/${OWNER_REPO}",
    "branch": "${BRANCH}",
    "metadata": {
        "sbom_lite_path": "${SBOM_FILE_PATH}"
    },
    "file_paths": [],
    "asset_id": "$SILK_GROUP"
}
EOF
)
# curl -X 'POST' \
#   'https://silkapi.us1.app.silk.security/api/v1/raw/asset_group' \
#   -H "accept: application/json" -H "Authorization: ${SILK_JWT_TOKEN}" \
#   -H 'Content-Type: application/json' \
#   -d "$json_payload"

echo "Create a temp sbom."
TMP_SBOM=sbom-for-${BRANCH}.json
podman run --platform="linux/amd64" --rm -v $(pwd):/pwd \
  ${ARTIFACTORY_IMAGE}/silkbomb:1.0 \
  update --sbom-out /pwd/${TMP_SBOM}

echo "Get the new timestamp and serial number."
SERIAL=$(jq -r '.serialNumber' ${TMP_SBOM})
TIMESTAMP=$(jq -r '.metadata.timestamp' ${TMP_SBOM})
rm ${TMP_SBOM}

echo "Replace the values in the existing sbom."
jq '.serialNumber = "'${SERIAL}'"' ${SBOM_FILE_PATH} > ${SBOM_FILE_PATH}
jq '.metadata.timestamp = "'${TIMESTAMP}'"' ${SBOM_FILE_PATH} > ${SBOM_FILE_PATH}

echo "Update the workflow with the silk asset group and evergreen project."
sed -i 's/SILK_ASSET_GROUP.*/SILK_ASSET_GROUP: '${SILK_GROUP}'/' ${RELEASE_WORKFLOW_PATH}
sed -i 's/EVERGREEN_PROJECT.*/EVERGREEN_PROJECT: '${EVERGREEN_PROJECT}'/' ${RELEASE_WORKFLOW_PATH}

echo "Add the changed files."
git --no-pager diff
git add ${SBOM_FILE_PATH} ${RELEASE_WORKFLOW_PATH}