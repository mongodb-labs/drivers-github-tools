#!/usr/bin/env bash
set -eu

echo "Normalize secrets variable names"
prefix=$(echo $AWS_SECRET_ID | tr '[:lower:]' '[:upper:]' | sed -r 's/[-/]+/_/g')
prefix=${prefix}_
vars=$(compgen -A variable | grep $prefix | tr '\n' ' ')
for var in $vars; do
     new_key=$(echo $var | sed "s/$prefix//g")
     declare $new_key=${!var}
done

echo "::group::Set up ECR Access"
git clone https://github.com/mongodb-labs/drivers-evergreen-tools
pushd drivers-evergreen-tools/.evergreen/docker
bash setup.sh
popd
rm -rf drivers-evergreen-tools
echo "::endgroup::"

echo "Set up envfile for garasign"
GARASIGN_ENVFILE=/tmp/garasign-envfile
cat << EOF > $GARASIGN_ENVFILE
GRS_CONFIG_USER1_USERNAME=$GARASIGN_USERNAME
GRS_CONFIG_USER1_PASSWORD=$GARASIGN_PASSWORD
EOF

if [ -n "${SILKBOMB_USER:-}" ]; then
  echo "Set up envfile for silkbomb"
  SILKBOMB_ENVFILE=/tmp/silkbomb-envfile
  cat << EOF > $SILKBOMB_ENVFILE
SILK_CLIENT_ID=${SILKBOMB_USER}
SILK_CLIENT_SECRET=${SILKBOMB_KEY}
EOF
fi

if [ -n "${KONDUKTO_TOKEN:-}" ]; then
  echo "Setting up envfile for Kondukto"
  KONDUKTO_ENVFILE=/tmp/kondukto-envfile
  cat << EOF > $KONDUKTO_ENVFILE
KONDUKTO_TOKEN=${KONDUKTO_TOKEN}
EOF
fi

echo "Set up output directories"
export RELEASE_ASSETS=/tmp/release-assets
mkdir $RELEASE_ASSETS
echo "$GITHUB_RUN_ID" > $RELEASE_ASSETS/release_run_id.txt
export S3_ASSETS=/tmp/s3-assets
mkdir $S3_ASSETS

echo "Set up global variables"
cat <<EOF >> $GITHUB_ENV
AWS_BUCKET=${RELEASE_ASSETS_BUCKET:-}
GPG_KEY_ID=$GPG_KEY_ID
GPG_PUBLIC_URL=${GPG_PUBLIC_URL:-}
GARASIGN_ENVFILE=$GARASIGN_ENVFILE
SILKBOMB_ENVFILE=${SILKBOMB_ENVFILE:-}
KONDUKTO_ENVFILE=${KONDUKTO_ENVFILE:-}
ECR_REGISTRY=${ECR_REGISTRY:-}
RELEASE_ASSETS=$RELEASE_ASSETS
S3_ASSETS=$S3_ASSETS
SECURITY_REPORT_URL=${SECURITY_REPORT_URL:-}
EOF

echo "Set up git credentials"
git config user.email "167856002+mongodb-dbx-release-bot[bot]@users.noreply.github.com"
git config user.name "mongodb-dbx-release-bot[bot]"