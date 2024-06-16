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

# Handle GitHub Release
if [ "$PUSH_CHANGES" == "true" ]; then
    push $GITHUB_WORKSPACE
    gh release create ${VERSION} --draft --verify-tag --title ${VERSION} -F github.md
    gh release upload ${VERSION} $RELEASE_ASSETS/*.*
    gh release view ${VERSION} >> $GITHUB_STEP_SUMMARY
    popd
else
    echo "## Skipping draft release with notes:" >> $GITHUB_STEP_SUMMARY
    cat github.md >> $GITHUB_STEP_SUMMARY
fi
rm github.md