#!/usr/bin/env bash
# Bump the version, commit it with a signature and push if requested.
# Environment: VERSION (required), VERSION_BUMP_SCRIPT, COMMIT_TEMPLATE, PUSH_COMMIT,
# WORKING_DIRECTORY, ECR_REPOSITORY, GPG_KEY_ID, GPG_PUBLIC_URL.
set -eux

VERSION_BUMP_SCRIPT="${VERSION_BUMP_SCRIPT:-}"
PUSH_COMMIT="${PUSH_COMMIT:-true}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"
GPG_PUBLIC_URL="${GPG_PUBLIC_URL:-}"
# An empty value would override the default of git-sign.sh.
[ -n "${ECR_REPOSITORY:-}" ] || unset ECR_REPOSITORY
[ -n "${COMMIT_TEMPLATE:-}" ] || COMMIT_TEMPLATE='BUMP ${VERSION}'

if [ -n "${VERSION_BUMP_SCRIPT}" ]; then
  (cd "${WORKING_DIRECTORY}" && eval "${VERSION_BUMP_SCRIPT} ${VERSION}")
fi

export VERSION
COMMIT_MESSAGE=$(echo "${COMMIT_TEMPLATE}" | envsubst)

COMMIT_ARGS=(-a -m "${COMMIT_MESSAGE}")
if [ -n "${GPG_PUBLIC_URL}" ]; then
  COMMIT_ARGS+=(-m "PGP-Signing-Key: ${GPG_PUBLIC_URL}")
fi
COMMIT_ARGS+=(-s "--gpg-sign=${GPG_KEY_ID}")
COMMAND=$(printf 'git commit'; printf ' %q' "${COMMIT_ARGS[@]}")
export COMMAND
bash "$(dirname "${BASH_SOURCE[0]}")/../git-sign/git-sign.sh"

if [ "${PUSH_COMMIT}" == "true" ]; then
  if git ls-remote --heads --exit-code origin "$(git symbolic-ref --short HEAD)" &>/dev/null; then
    git push origin
  else
    git push --set-upstream origin "$(git symbolic-ref --short HEAD)"
  fi
  echo "Pushed version bump: ${VERSION}" >> "$GITHUB_STEP_SUMMARY"
else
  echo "Created version bump (no push): ${VERSION}" >> "$GITHUB_STEP_SUMMARY"
fi
