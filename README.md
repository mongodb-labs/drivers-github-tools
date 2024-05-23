# drivers-github-tools

> [!IMPORTANT]
> This Repository is NOT a supported MongoDB product

This repository contains GitHub Actions that are common to drivers.

## Setup

There is a common setup action that is meant to be run before all
other actions.  It handles fetching secrets from AWS Secrets Manager,
signing into Artifactory, setting up Garasign credentials, and
setting up environment variables used in other actions.
The action requires `id-token: write` permissions.

```yaml
- name: setup
  uses: mongodb/drivers-github-tools/setup@v2
  with:
    aws_role_arn: ${{ secrets.AWS_ROLE_ARN }}
    aws_region_name: ${{ vars.AWS_REGION_NAME }}
    aws_secret_id: ${{ secrets.AWS_SECRET_ID }}
```

## Signing tools

The actions in the `garasign` folder are used to sign artifacts using the team's
GPG key.

### git-sign

Use this action to create signed git artifacts:

```yaml
- name: Setup
  uses: mongodb/drivers-github-tools/setup@v2
  with:
    ...

- name: Create signed commit
  uses: mongodb/drivers-github-tools/git-sign@v2

- name: Create signed tag
  uses: mongodb/drivers-github-tools/git-sign@v2
```

### gpg-sign

This action is used to create detached signatures for files:

```yaml
- name: Setup
  uses: mongodb/drivers-github-tools/setup@main
  with:
    ...

- name: Create detached signature
  uses: mongodb/drivers-github-tools/gpg-sign@main
  with:
    filenames: somefile.ext
```

The action will create a signature file `somefile.ext.sig` in the working
directory.

You can also supply a glob pattern to sign a group of files:

```yaml
- name: Setup
  uses: mongodb/drivers-github-tools/setup@main
  with:
    ...

- name: Create detached signature
  uses: mongodb/drivers-github-tools/garasign/gpg-sign@main
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
  uses: mongodb/drivers-github-tools/setup@main
  with:
    ...

- name: Create Authorized Publication Report
  uses: mongodb/drivers-github-tools/authorized-pub@main
  with:
    product_name: Mongo Python Driver
    release_version: ${{ github.ref_name }}
    filenames: dist/*
    token: ${{ github.token }}
```

## Python Helper Scripts

These scripts are opinionated helper scripts for Python releases.

### Bump and Tag

Bump the version and create a new tag.  Verify the tag.
Push the commit and tag to the source branch unless `dry_run` is set.

```yaml
- name: Setup
  uses: mongodb/drivers-github-tools/setup@main
  with:
    ...

- uses: mongodb/drivers-github-tools/python/bump-and-tag@main
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
  uses: mongodb/drivers-github-tools/setup@main
  with:
    ...

- uses: mongodb-labs/drivers-github-tools/python/publish@main
  with:
    version: ${{ inputs.version }}
    following_version: ${{ inputs.following_version }}
    version_bump_script: ./.github/scripts/bump-version.sh
    product_name: winkerberos
    token: ${{ github.token }}
    dry_run: ${{ inputs.dry_run }}
```