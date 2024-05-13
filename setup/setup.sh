#!/usr/bin/env bash
set -eu

echo "Fetch secrets..."
SECRETS_FILE=/tmp/secret-value.json
echo "$(aws secretsmanager get-secret-value --secret-id ${AWS_SECRET_ID} --query SecretString --output text)" > $SECRETS_FILE
# Ensure sensitive secrets are masked in logs.
ARTIFACTORY_USER=$(cat $SECRETS_FILE | jq -r '."artifactory-username"')
ARTIFACTORY_PASSWORD=$(cat $SECRETS_FILE | jq -r '."artifactory-password"')
echo "::add-mask::$ARTIFACTORY_PASSWORD"
GRS_CONFIG_USER1_USERNAME=$(cat $SECRETS_FILE | jq -r '."garasign-username"')
echo "::add-mask::$GRS_CONFIG_USER1_USERNAME"
GRS_CONFIG_USER1_PASSWORD=$(cat $SECRETS_FILE | jq -r '."garasign-password"')
echo "::add-mask::$GRS_CONFIG_USER1_PASSWORD"
GPG_PUBLIC_URL=$(cat $SECRETS_FILE | jq -r '."gpg-public-url"')
GPG_KEY_ID=$(cat $SECRETS_FILE | jq -r '."gpg-key-id"')
AWS_BUCKET=$(cat $SECRETS_FILE | jq -r '."release-assets-bucket"')
echo "::add-mask::$AWS_BUCKET"
APP_PRIVATE_KEY=$(cat $SECRETS_FILE | jq -r '."github-app-private-key"')
echo "::add-mask::$APP_PRIVATE_KEY"
APP_ID=$(cat $SECRETS_FILE | jq -r '."github-app-id"')
rm $SECRETS_FILE
echo "Fetch secrets... done."

echo "::group::Set up artifactory"
echo $ARTIFACTORY_PASSWORD | podman login -u $ARTIFACTORY_USER --password-stdin $ARTIFACTORY_REGISTRY
podman pull $ARTIFACTORY_REGISTRY/$ARTIFACTORY_IMAGE
echo "::endgroup::"

echo "Set up envfile for artifactory image"
GARASIGN_ENVFILE=/tmp/envfile
cat << EOF > $GARASIGN_ENVFILE
GRS_CONFIG_USER1_USERNAME=$GRS_CONFIG_USER1_USERNAME
GRS_CONFIG_USER1_PASSWORD=$GRS_CONFIG_USER1_PASSWORD
EOF

####################
# Generate App Token
# https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app#example-using-bash-to-generate-a-jwt
echo "Generate App Token"
client_id=$APP_ID

pem=$(echo $APP_PRIVATE_KEY | base64 --decode)

now=$(date +%s)
iat=$((${now} - 60)) # Issues 60 seconds in the past
exp=$((${now} + 600)) # Expires 10 minutes in the future

b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

header_json='{
    "typ":"JWT",
    "alg":"RS256"
}'
# Header encode
header=$( echo -n "${header_json}" | b64enc )

payload_json='{
    "iat":'"${iat}"',
    "exp":'"${exp}"',
    "iss":'"${client_id}"'
}'
# Payload encode
payload=$( echo -n "${payload_json}" | b64enc )

# Signature
header_payload="${header}"."${payload}"
signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") \
    <(echo -n "${header_payload}") | b64enc
)

# Create JWT
JWT="${header_payload}"."${signature}"
echo "::add-mask::$JWT"

# Set the git config for checkout
git config --global credential.https://github.com.username git
git config --global credential.https://github.com.password $JWT
####################

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

echo "Set up git config"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
git config --global user.name "github-actions[bot]"
