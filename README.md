# drivers-github-tools

> [!IMPORTANT]
> This Repository is NOT a supported MongoDB product

This repository contains GitHub Actions that are common to drivers.

## Secure Checkout

This action will perform a checkout with the GitHub App credentials.

```yaml
- name: secure-checkout
  uses: mongodb-labs/drivers-github-tools/secure-checkout@v2
  with:
    app_id: ${{ vars.APP_ID }}
    private_key: ${{ secrets.APP_PRIVATE_KEY }}
```

By default it will use the current `${{github.ref}}` if the `ref` parameter is
not given.  It will write the secure global variable `GH_TOKEN` that can be
used with the `gh` cli.


## Setup

There is a common setup action that is meant to be run before all
other actions.  It handles fetching secrets from AWS Secrets Manager,
signing into Artifactory, setting up Garasign credentials, and
setting up environment variables used in other actions.
The action requires `id-token: write` permissions.

```yaml
- name: setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    aws_role_arn: ${{ secrets.AWS_ROLE_ARN }}
    aws_region_name: ${{ vars.AWS_REGION_NAME }}
    aws_secret_id: ${{ secrets.AWS_SECRET_ID }}
```

> [!Note]
> You *must* use the `actions/checkout` action prior to calling the `setup` action,
> Since the `setup` action sets up git config that would be overridden by the
> `actions/checkout action`
>
> The following keys MUST be defined in the ``AWS_SECRET_ID`` vault:
> `artifactory-username`, `artifactory-password`, `garasign-username`
> `garasign-password`, `gpg-key-id`.  If uploading to an S3 bucket, also define
> `release-assets-bucket`.

## Signing tools

The actions in the `garasign` folder are used to sign artifacts using the team's
GPG key.

### git-sign

Use this action to create signed git artifacts:

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Create signed commit
  uses: mongodb-labs/drivers-github-tools/git-sign@v2
  with:
    command: "git commit -m 'Commit' -s --gpg-sign=${{ env.GPG_KEY_ID }}"

- name: Create signed tag
  uses: mongodb-labs/drivers-github-tools/git-sign@v2
  with:
    command: "git tag -m 'Tag' -s --local-user=${{ env.GPG_KEY_ID }} -a <tag>"
```

### gpg-sign

This action is used to create detached signatures for files:

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Create detached signature
  uses: mongodb-labs/drivers-github-tools/gpg-sign@v2
  with:
    filenames: somefile.ext
```

The action will create a signature file `somefile.ext.sig` in the working
directory.

You can also supply a glob pattern to sign a group of files:

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Create detached signature
  uses: mongodb-labs/drivers-github-tools/garasign/gpg-sign@v1
  with:
    filenames: dist/*
```

## Reporting tools

The following tools are meant to aid in generating Software Security Development Lifecycle
reports associated with a product release.

### Authorized Publication

This action will create a record of authorized publication on distribution channels.
It will create the file `$S3_ASSETS/authorized_publication.txt`

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Create Authorized Publication Report
  uses: mongodb-labs/drivers-github-tools/authorized-pub@v2
  with:
    product_name: Mongo Python Driver
    release_version: ${{ github.ref_name }}
    filenames: dist/*
    token: ${{ github.token }}
```

### Software Bill of Materials (SBOM)

This action will download an Augmented SBOM file in `$RELEASE_ASSETS/sbom.json`.

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Create SBOM
  uses: mongodb-labs/drivers-github-tools/sbom@v2
  with:
    silk_asset_group: mongodb-python-driver
```

### Code Scanning Alerts

This action will export all dismissed and open alerts to a SARIF file. By
default, this file is named `code-scanning-alerts.json` and placed in the
working directory.

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Export Code Scanning Alerts
  uses: mongodb-labs/drivers-github-tools/code-scanning-export@v2
```

## Upload S3 assets

A number of scripts create files in the `tmp/s3_assets` folder, which then can
be uploaded to the product's S3 bucket:

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- name: Upload S3 assets
  uses: mongodb-labs/drivers-github-tools/upload-s3-assets@v2
  with:
    version: <release version>
    product_name: <product_name>
```

Optionally, you can specify which files to upload using the `filenames` input.
By default, all files in the S3 directory are uploaded. When the `dry_run` input
is set to anything other than `false`, no files are uploaded, but instead the
filename along with the resulting location in the bucket is printed.

## Python Helper Scripts

These scripts are opinionated helper scripts for Python releases.

### Bump and Tag

Bump the version and create a new tag.  Verify the tag.
Push the commit and tag to the source branch unless `dry_run` is set.

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- uses: mongodb-labs/drivers-github-tools/python/bump-and-tag@v2
  with:
    version: ${{ inputs.version }}
    version_bump_script: ./.github/scripts/bump-version.sh
    dry_run: ${{ inputs.dry_run }}
```

### Publish

Handles tasks related to publishing Python packages, including
signing `dist` file and publishing the `dist` files to PyPI.
It will also push the following (dev) version to the source branch.
It will create a draft GitHub release and attach the signature files.
Finally, it will publish a report to the appropriate S3 bucket.
If `dry_run` is set, nothing will be published or pushed.

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v2
  with:
    ...

- uses: mongodb-labs/drivers-github-tools/python/publish@v2
  with:
    version: ${{ inputs.version }}
    following_version: ${{ inputs.following_version }}
    version_bump_script: ./.github/scripts/bump-version.sh
    product_name: winkerberos
    token: ${{ github.token }}
    dry_run: ${{ inputs.dry_run }}
```
