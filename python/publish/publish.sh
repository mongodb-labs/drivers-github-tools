#!/usr/bin/env bash

set -eux

if [ "$DRY_RUN" == "false" ]; then
    PUSH_CHANGES=true
    echo "Creating draft release with attached files"
    gh release create ${VERSION} --draft --verify-tag --title ${VERSION} --notes ""
    gh release upload ${VERSION} $RELEASE_ASSETS/*.*
    gh release view ${VERSION} >> $GITHUB_STEP_SUMMARY
else
    echo "Dry run, not creating GitHub Release"
    ls -ltr $RELEASE_ASSETS
    PUSH_CHANGES=false
fi

# Ensure a clean repo
git clean -dffx
git pull origin ${GITHUB_REF}

# Handle push_changes output.
echo "push_changes=$PUSH_CHANGES" >> $GITHUB_OUTPUT