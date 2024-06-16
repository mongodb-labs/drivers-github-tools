#! /bin/bash
set -eux

# Handle DRY_RUN
if [ "$PUSH_CHANGES" != "true" ]; then
    export DRY_RUN=true
else
    export DRY_RUN=false
fi
echo "DRY_RUN=$DRY_RUN" >> $GITHUB_ENV

# Generate notes
go run notes.go $VERSION $PREV_VERSION
cat forum.md >> $GITHUB_STEP_SUMMARY
rm forum.md

echo "---" >> $GITHUB_STEP_SUMMARY

NOTES_FILE=$(pwd)/github.md

# Handle GitHub Release
if [ "$PUSH_CHANGES" == "true" ]; then
    pushd $GITHUB_WORKSPACE || exit 1
    TITLE="MongoDB Go Driver ${VERSION}"
    gh release create v${VERSION} --draft --verify-tag --title "$TITLE" -F $NOTES_FILE
    gh release upload v${VERSION} $RELEASE_ASSETS/*.*
    JSON="url,tagName,assets,author,createdAt"
    JQ='.url,.tagName,.author.login,.createdAt,.assets[].name'
    gh release view --json $JSON --jq $JQ v${VERSION} >> $GITHUB_STEP_SUMMARY
    popd || exit 1
else
    echo "## Skipping draft release with notes:" >> $GITHUB_STEP_SUMMARY
    cat $NOTES_FILE >> $GITHUB_STEP_SUMMARY
fi
rm $NOTES_FILE