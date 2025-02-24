#! /bin/bash
set -eu

echo "Create or checkout the branch."
OWNER_REPO="${GITHUB_REPOSITORY}"
git ls-remote --exit-code --heads https://github.com/${OWNER_REPO}.git refs/heads/$BRANCH || {
  git branch $BRANCH $BASE_REF
}
git fetch origin $BRANCH || true
git checkout $BRANCH

echo "Update the workflow with the new evergreen project."
sed -i 's/EVERGREEN_PROJECT:.*/EVERGREEN_PROJECT: '${EVERGREEN_PROJECT}'/' ${RELEASE_WORKFLOW_PATH}

echo "Add the changed files."
git --no-pager diff
git add ${SBOM_FILE_PATH} ${RELEASE_WORKFLOW_PATH}