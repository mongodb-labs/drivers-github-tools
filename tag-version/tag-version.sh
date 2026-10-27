#!/usr/bin/env bash
# Tag the version with a signature and push the tag if requested.
# Environment: VERSION (required), TAG_TEMPLATE, TAG_MESSAGE_TEMPLATE, PUSH_TAG,
# ECR_REPOSITORY, GPG_KEY_ID, GPG_PUBLIC_URL.
set -eux

[ -n "${TAG_TEMPLATE:-}" ] || TAG_TEMPLATE='${VERSION}'
[ -n "${TAG_MESSAGE_TEMPLATE:-}" ] || TAG_MESSAGE_TEMPLATE='Release ${VERSION}'
PUSH_TAG="${PUSH_TAG:-true}"
GPG_PUBLIC_URL="${GPG_PUBLIC_URL:-}"
# An empty value would override the default of git-sign.sh.
[ -n "${ECR_REPOSITORY:-}" ] || unset ECR_REPOSITORY

export VERSION
TAG=$(echo "${TAG_TEMPLATE}" | envsubst)
TAG_MESSAGE=$(echo "${TAG_MESSAGE_TEMPLATE}" | envsubst)
export TAG
echo "TAG=$TAG" >> "$GITHUB_ENV"
echo "TAG_MESSAGE=$TAG_MESSAGE" >> "$GITHUB_ENV"

TAG_ARGS=(-a "${TAG}" -m "${TAG_MESSAGE}")
if [ -n "${GPG_PUBLIC_URL}" ]; then
  TAG_ARGS+=(-m "PGP-Signing-Key: ${GPG_PUBLIC_URL}")
fi
TAG_ARGS+=(-s "--local-user=${GPG_KEY_ID}")
COMMAND=$(printf 'git tag'; printf ' %q' "${TAG_ARGS[@]}")
export COMMAND
bash "$(dirname "${BASH_SOURCE[0]}")/../git-sign/git-sign.sh"

if [ -n "${GPG_PUBLIC_URL}" ]; then
  curl "${GPG_PUBLIC_URL}" --output /tmp/signature.pub
  gpg --import /tmp/signature.pub
  git verify-tag "${TAG}"
else
  echo "Skipping tag verification"
fi

if [ "${PUSH_TAG}" == "true" ]; then
  git push origin tag "${TAG}"
  echo "Pushed tag: ${TAG}" >> "$GITHUB_STEP_SUMMARY"
else
  echo "Created tag (no push): ${TAG}" >> "$GITHUB_STEP_SUMMARY"
fi
