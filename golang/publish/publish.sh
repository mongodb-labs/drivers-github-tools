#! /bin/bash
set -eux

# Handle DRY_RUN
if [ "$PUSH_CHANGES" != "true" ]; then
    export DRY_RUN=true
else
    export DRY_RUN=false
fi
echo "DRY_RUN=$DRY_RUN" >> $GITHUB_ENV

# Handle GitHub Release
if [ "$PUSH_CHANGES" == "true" ]; then
    pushd $GITHUB_WORKSPACE || exit 1
    TITLE="MongoDB Go Driver ${VERSION}"

    # Create draft release with generated release notes
    gh release create v${VERSION} --draft --verify-tag --title "$TITLE" --generate-notes

    # Extract generated release notes to file
    gh release view v${VERSION} --json body --template '{{ .body }}' >> changelog

    NOTES_FILE=$(pwd)/changelog

    popd || exit 1

    # Generate release notes
    go run notes.go $VERSION $PREV_VERSION $NOTES_FILE
    cat forum.md >> $GITHUB_STEP_SUMMARY
    rm forum.md

    echo "---" >> $GITHUB_STEP_SUMMARY

    NOTES_FILE=$(pwd)/github.md

    pushd $GITHUB_WORKSPACE || exit 1

    # Update release notes with generated version and upload release assets
    gh release create v${VERSION} -F $NOTES_FILE
    gh release upload v${VERSION} $RELEASE_ASSETS/*.*
    JSON="url,tagName,assets,author,createdAt"
    JQ='.url,.tagName,.author.login,.createdAt,.assets[].name'
    echo "\## $TITLE" >> $GITHUB_STEP_SUMMARY
    gh release view --json $JSON --jq $JQ v${VERSION} >> $GITHUB_STEP_SUMMARY

    popd || exit 1
else
    echo "## Skipping draft release" >> $GITHUB_STEP_SUMMARY
fi
rm $NOTES_FILE
