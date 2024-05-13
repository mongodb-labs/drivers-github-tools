#!/usr/bin/env bash
set -eu

echo "Normalize secrets variable names"
prefix=$(echo $AWS_SECRET_ID | tr '[:lower:]' '[:upper:]' | sed -r 's/[-/]+/_/g')
echo "PREFIX=$prefix"
prefix=${prefix}_
compgen -A variable $prefix | while read v; do
    new_key=$(echo $v | sed "s/$prefix//g")
    echo "hello $new_key"
    declare -g "$new_key=${!v}"
done

echo "::group::Set up artifactory"
echo $ARTIFACTORY_PASSWORD | podman login -u $ARTIFACTORY_USERNAME --password-stdin $ARTIFACTORY_REGISTRY
podman pull $ARTIFACTORY_REGISTRY/$ARTIFACTORY_IMAGE
echo "::endgroup::"

echo "Set up envfile for artifactory image"
GARASIGN_ENVFILE=/tmp/envfile
cat << EOF > $GARASIGN_ENVFILE
GRS_CONFIG_USER1_USERNAME=$GRS_CONFIG_USER1_USERNAME
GRS_CONFIG_USER1_PASSWORD=$GRS_CONFIG_USER1_PASSWORD
EOF

echo "Set outputs for GitHub App auth"
pem=$(echo $APP_PRIVATE_KEY | base64 --decode)
echo "app-id=$APP_ID" >> "$GITHUB_OUTPUT"
# Ensure the value is not printed to logs.
echo "::add-mask::$pem"
echo "private-key=$pem" >> "$GITHUB_OUTPUT"

echo "Set up output directories"
export RELEASE_ASSETS=/tmp/release-assets
mkdir $RELEASE_ASSETS
echo "$GITHUB_RUN_ID" > $RELEASE_ASSETS/release_run_id.txt
export S3_ASSETS=/tmp/s3-assets
mkdir $S3_ASSETS

echo "Set up global variables"
cat <<EOF >> $GITHUB_ENV
AWS_BUCKET=$AWS_BUCKET
GPG_KEY_ID=$GPG_KEY_ID
GPG_PUBLIC_URL=$GPG_PUBLIC_URL
GARASIGN_ENVFILE=$GARASIGN_ENVFILE
ARTIFACTORY_IMAGE=$ARTIFACTORY_IMAGE
ARTIFACTORY_REGISTRY=$ARTIFACTORY_REGISTRY
RELEASE_ASSETS=$RELEASE_ASSETS
S3_ASSETS=$S3_ASSETS
EOF
