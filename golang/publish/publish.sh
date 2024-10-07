#! /bin/bash
set -eux

# Handle DRY_RUN
if [ "$PUSH_CHANGES" != "true" ]; then
    export DRY_RUN=true
else
    export DRY_RUN=false
fi
echo "DRY_RUN=$DRY_RUN" >> $GITHUB_ENV

# Handle cloud release versions
TAG_NAME="v${VERSION}"
PREV_TAG_NAME="v${PREV_VERSION}"
if [[ "${TAG_NAME}" =~ ^cloud.* ]]; then
  TAG_NAME="${VERSION}"
  PREV_TAG_NAME="${PREV_VERSION}"
fi

# Generate notes
go run notes.go $TAG_NAME $PREV_TAG_NAME
cat forum.md >> $GITHUB_STEP_SUMMARY
rm forum.md

echo "---" >> $GITHUB_STEP_SUMMARY

NOTES_FILE=$(pwd)/github.md

# Handle GitHub Release
if [ "$PUSH_CHANGES" == "true" ]; then
    pushd $GITHUB_WORKSPACE || exit 1
    TITLE="MongoDB Go Driver ${VERSION}"
    gh release create ${TAG_NAME} --draft --verify-tag --title "$TITLE" -F $NOTES_FILE
    gh release upload ${TAG_NAME} $RELEASE_ASSETS/*.*
    JSON="url,tagName,assets,author,createdAt"
    JQ='.url,.tagName,.author.login,.createdAt,.assets[].name'
    echo "\## $TITLE" >> $GITHUB_STEP_SUMMARY
    gh release view --json $JSON --jq $JQ ${TAG_NAME} >> $GITHUB_STEP_SUMMARY
    popd || exit 1
else
    echo "## Skipping draft release with notes:" >> $GITHUB_STEP_SUMMARY
    cat $NOTES_FILE >> $GITHUB_STEP_SUMMARY
fi
rm $NOTES_FILE