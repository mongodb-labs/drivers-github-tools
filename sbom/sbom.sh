#!/usr/bin/env bash
# Augment the SBOM and write it to the release assets and s3 assets folders.
# Environment: SBOM_IN_PATH, SBOM_FILE_NAME, KONDUKTO_SUB_PROJECT, ECR_REGISTRY, ECR_REPOSITORY.
set -eu

ECR_REGISTRY="${ECR_REGISTRY:-901841024863.dkr.ecr.us-east-1.amazonaws.com}"
ECR_REPOSITORY="${ECR_REPOSITORY:-release-infrastructure/silkbomb:2.0}"
KONDUKTO_SUB_PROJECT="${KONDUKTO_SUB_PROJECT:-}"

if [ -n "${KONDUKTO_SUB_PROJECT}" ]; then
  KONDUKTO_BRANCH="${GITHUB_REF_NAME}_${KONDUKTO_SUB_PROJECT}"
else
  KONDUKTO_BRANCH="${GITHUB_REF_NAME}"
fi
echo "Generating SBOM file for ${KONDUKTO_BRANCH}..."
echo "Updating SBOM file..."
docker run --platform="linux/amd64" -i --rm -v ${RELEASE_ASSETS}:/pwd -v "$(pwd)":/repo \
  --env-file=${KONDUKTO_ENVFILE} \
  ${ECR_REGISTRY}/${ECR_REPOSITORY} \
  update --sbom-in /repo/${SBOM_IN_PATH} --sbom-out /pwd/cyclonedx.sbom.json --generate-new-serial-number
echo "Augumenting SBOM file..."
docker run --platform="linux/amd64" -i --rm -v ${RELEASE_ASSETS}:/pwd -v "$(pwd)":/repo \
  --env-file=${KONDUKTO_ENVFILE} \
  ${ECR_REGISTRY}/${ECR_REPOSITORY} \
  augment --sbom-in /pwd/cyclonedx.sbom.json --repo ${GITHUB_REPOSITORY} --branch ${KONDUKTO_BRANCH} --sbom-out /pwd/cyclonedx.sbom.json
cp ${RELEASE_ASSETS}/cyclonedx.sbom.json ${S3_ASSETS}/${SBOM_FILE_NAME}
echo "Generating SBOM file for ${KONDUKTO_BRANCH}... done."
