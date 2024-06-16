#! /bin/bash

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

NOTES_FILE=$(pwd)/github.md

# Handle GitHub Release
if [ "$PUSH_CHANGES" == "true" ]; then
    pushd $GITHUB_WORKSPACE
    TITLE="MongoDB Go Driver ${VERSION}
    gh release create ${VERSION} --draft --verify-tag --title $TITLE -F $NOTES_FILE
    gh release upload v${VERSION} $RELEASE_ASSETS/*.*
    gh release view v${VERSION} >> $GITHUB_STEP_SUMMARY
    popd
else
    echo "## Skipping draft release with notes:" >> $GITHUB_STEP_SUMMARY
    cat $NOTES_FILE >> $GITHUB_STEP_SUMMARY
fi
rm $NOTES_FILE