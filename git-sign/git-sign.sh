#!/usr/bin/env bash
# Run a git command in a signing container with GPG keys loaded.
# Environment: COMMAND (required), ECR_REGISTRY, ECR_REPOSITORY.
set -eu

ECR_REGISTRY="${ECR_REGISTRY:-901841024863.dkr.ecr.us-east-1.amazonaws.com}"
ECR_REPOSITORY="${ECR_REPOSITORY:-release-infrastructure/garasign-git}"

WORKING_DIR=/home/git-checkout
docker run \
  --env-file=$GARASIGN_ENVFILE \
  --rm \
  -v $(pwd):$WORKING_DIR \
  -w $WORKING_DIR \
  ${ECR_REGISTRY}/${ECR_REPOSITORY} \
  /bin/bash -c "git config --global --add safe.directory $WORKING_DIR && gpgloader && ${COMMAND}"
