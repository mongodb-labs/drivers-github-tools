#!/usr/bin/env bash

set -eux

if [ "$DRY_RUN" == "false" ]; then
    echo "Creating draft release with attached files"
    gh release create ${VERSION} --draft --verify-tag --title ${VERSION} --notes ""
    gh release upload ${VERSION} $RELEASE_ASSETS/*.*
    gh release view ${VERSION} >> $GITHUB_STEP_SUMMARY
else
    echo "Dry run, not creating GitHub Release"
    ls -ltr $RELEASE_ASSETS
fi
