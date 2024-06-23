#!/usr/bin/env bash

set -eux

if [ "$DRY_RUN" == "false" ]; then
    PUSH_CHANGES=true
    echo "Creating draft release with attached files"
    TITLE="${PRODUCT_NAME} ${VERSION}"
    gh release create ${VERSION} --draft --verify-tag --title "${TITLE}" --notes "Community notes: <link>"
    gh release upload ${VERSION} $RELEASE_ASSETS/*.*
    JSON="url,tagName,assets,author,createdAt"
    JQ='.url,.tagName,.author.login,.createdAt,.assets[].name'
    echo "\## $TITLE" >> $GITHUB_STEP_SUMMARY
    gh release view --json $JSON --jq $JQ ${VERSION} >> $GITHUB_STEP_SUMMARY
else
    echo "Dry run, not creating GitHub Release"
    ls -ltr $RELEASE_ASSETS
    PUSH_CHANGES=false
fi

# Handle push_changes output.
echo "push_changes=$PUSH_CHANGES" >> $GITHUB_OUTPUT