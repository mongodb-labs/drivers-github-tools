# Python Labs Actions

Opinionated helper actions for Python releases in MongoDB Labs. Unlike the
[regular Python actions](../python/README.md), these do not generate the SSDLC
compliance assets or upload anything to S3.

## Pre-Publish

Create a new tag.  Verify the tag.
Push the commit and tag to the source branch unless `dry_run` is set.

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v3
  with:
    ...

- uses: mongodb-labs/drivers-github-tools/python-labs/pre-publishv2
  with:
    version_bump_script: ./.github/scripts/bump-version.sh
    dry_run: ${{ inputs.dry_run }}
```

## Post-publish

To be run after separately publishing the [Python package](https://github.com/pypa/gh-action-pypi-publish#trusted-publishing).
Handles follow-up tasks related to publishing Python packages.
It will push the following (dev) version to the source branch.
It will create a draft GitHub release with generated release notes.
If `dry_run` is set, nothing will be pushed.

The jobs should look something like:

```yaml
publish:
  name: Upload release to PyPI
  runs-on: ubuntu-latest
  environment: release
  permissions:
    id-token: write
  steps:
    - name: Download all the dists
      uses: actions/download-artifact@v4
      with:
        name: all-dist-${{ github.run_id }}
        path: dist/
    - name: Publish package distributions to PyPI
      if: inputs.dry_run == 'false'
      uses: pypa/gh-action-pypi-publish@release/v1

post-publish:
  needs: [publish]
  name: Handle post-publish actions
  runs-on: ubuntu-latest
  environment: release
  permissions:
    id-token: write
    contents: write
    attestations: write
    security-events: write
  steps:
  - name: Setup
    uses: mongodb-labs/drivers-github-tools/setup@v3
    with:
      ...

  - uses: mongodb-labs/drivers-github-tools/python-labs/post-publish@v3
    with:
      following_version: ${{ inputs.following_version }}
      version_bump_script: ./.github/scripts/bump-version.sh
      product_name: python-bsonjs
      token: ${{ github.token }}
      dry_run: ${{ inputs.dry_run }}
```
