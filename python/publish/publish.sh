#!/usr/bin/env bash

set -eux

mv code-scanning-alerts.json $S3_ASSETS

if [ "$DRY_RUN" == "false" ]; then
    echo "Uploading Release Reports"
    TARGET=s3://${AWS_BUCKET}/${PRODUCT_NAME}/${VERSION}
    aws s3 cp $S3_ASSETS $TARGET --recursive

    echo "Creating draft release with attached files"
    gh release create ${VERSION} --draft --verify-tag --title ${VERSION} --notes ""
    gh release upload ${VERSION} $RELEASE_ASSETS/*.*
    gh release view ${VERSION} >> $GITHUB_STEP_SUMMARY
else
    echo "Dry run, not uploading to S3 or creating GitHub Release"
    ls -ltr $RELEASE_ASSETS
    ls -ltr $S3_ASSETS
fi
