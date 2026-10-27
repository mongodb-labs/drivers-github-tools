#!/usr/bin/env bash
# Create detached signatures for files and move them to the release assets directory.
# Environment: FILENAMES (required, can be a glob pattern), ECR_REGISTRY, ECR_REPOSITORY.
set -eux

ECR_REGISTRY="${ECR_REGISTRY:-901841024863.dkr.ecr.us-east-1.amazonaws.com}"
ECR_REPOSITORY="${ECR_REPOSITORY:-release-infrastructure/garasign-git}"

if [[ $FILENAMES == *\** ]]; then
  # shellcheck disable=SC2086
  FILENAMES=$(ls $FILENAMES | tr '\n' ' ')
fi

docker run \
  --env-file="$GARASIGN_ENVFILE" \
  --rm \
  -v "$(pwd)":"$(pwd)" \
  -w "$(pwd)" \
  "${ECR_REGISTRY}/${ECR_REPOSITORY}" \
  /bin/bash -c "gpgloader && for filename in ${FILENAMES}; do gpg --detach-sign --armor --output \${filename}.sig \${filename}; done"

for filename in $FILENAMES; do mv "${filename}.sig" "$RELEASE_ASSETS"; done
