# Python Actions

Opinionated helper actions for Python CI and releases. See the
[top-level README](../README.md) for actions shared across all drivers.

## Setup

Puts Python, uv, and just on `PATH`, replacing the setup steps that Python driver
repos repeat in every CI job.

```yaml
- uses: mongodb-labs/drivers-github-tools/python/setup@v3
  with:
    python-version: "3.10"
```

Python comes from `actions/setup-python`, which is faster than having uv download
a managed interpreter. The action then exports `UV_PYTHON` as the requested
version, so the project's `pyproject.toml` and `.python-version` do not change
the choice, and `UV_PYTHON_PREFERENCE=only-system`, so uv never downloads an
interpreter of its own.

`UV_PYTHON` holds a version rather than an interpreter path. A path would also
outrank a virtual environment that the job activates later, so a job doing its
own `uv venv` would find `uv pip install` targeting the interpreter behind its
back.

The action runs no just recipes. A job that needs project dependencies runs its
own `just install` step after this one.

The action sets no resolution policy. A repo that wants to hold back newly
published packages configures `exclude-newer` in its own `pyproject.toml` or
`uv.toml`, or commits a `uv.lock`.

`enable-cache` defaults to `true` and is passed through to `astral-sh/setup-uv`.

`allow-prereleases` defaults to `true`, so a Python version with no stable release
resolves to the prerelease instead of failing. Set it to `"false"` for a job that
should fail instead of testing against a beta.

## Pre-Publish

Bump the version and create a new tag.  Verify the tag.
Push the commit and tag to the source branch unless `dry_run` is set.

```yaml
- name: Setup
  uses: mongodb-labs/drivers-github-tools/setup@v3
  with:
    ...

- uses: mongodb-labs/drivers-github-tools/python/pre-publish@v3
  with:
    version: ${{ inputs.version }}
    version_bump_script: ./.github/scripts/bump-version.sh
    dry_run: ${{ inputs.dry_run }}
```

## Post-publish

To be run after separately publishing the [Python package](https://github.com/pypa/gh-action-pypi-publish#trusted-publishing).
Handles follow-up tasks related to publishing Python packages, including
signing `dist` files and uploading report assets to S3.
It will also push the following (dev) version to the source branch.
It will create a draft GitHub release and attach the signature files.
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

  - uses: mongodb-labs/drivers-github-tools/python/post-publish@v3
    with:
      version: ${{ inputs.version }}
      following_version: ${{ inputs.following_version }}
      version_bump_script: ./.github/scripts/bump-version.sh
      product_name: winkerberos
      token: ${{ github.token }}
      dry_run: ${{ inputs.dry_run }}
```

## uv Lock Update

This action runs `uv lock --upgrade` and opens a pull request with the resulting
lock file changes. It maintains a single open pull request: a subsequent run
updates the existing one rather than opening a second.

The caller checks out the repository and puts `uv` on `PATH`.

```yaml
name: Update uv.lock

on:
  schedule:
    - cron: "0 7 * * 1"
  workflow_dispatch:

# Runs must serialize: two at once would force push the same branch and race on
# the pull request. Keep the group static rather than keying it on the ref.
concurrency:
  group: uv-lock-update
  cancel-in-progress: false

jobs:
  update-lock:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: astral-sh/setup-uv@v8
      - uses: mongodb-labs/drivers-github-tools/python/uv-lock-update@v3
        with:
          app_id: ${{ vars.APP_ID }}
          private_key: ${{ secrets.APP_PRIVATE_KEY }}
```

`app_id` and `private_key` are required unless `dry_run` is true.

`base` defaults to the ref the workflow ran on, which is what a checkout with no
`ref` takes. If you check out a different ref, set `base` to match it, or the
pull request will contain every unrelated commit between the two branches.

Every label named in `labels` must already exist in the repository, because
GitHub rejects a pull request that asks for an unknown one.

Set `dry_run: true` to log the branch and pull request the action would have
created, without pushing or opening anything.

### Tracking Dependabot's uv

GitHub-hosted Dependabot runs the uv baked into its updater image, not the
uv your `[tool.uv] required-version` pin asks for
([dependabot-core#13199](https://github.com/dependabot/dependabot-core/issues/13199)).
The day the two diverge, Dependabot security updates stop arriving, with no
pull request and no failed check to show for it.

Set `track_dependabot_uv: true` to close that gap. The action resolves the
uv version from the `uv/Dockerfile` of the newest `dependabot-core` release
tag, and:

- Rewrites a pin that does not accept that version to
  `>=<dependabot uv>,<next minor>`, so Dependabot's uv is the floor and
  later patch releases flow without another rewrite.
- Commits the aligned pin in the same pull request as the lock update.
- Regenerates the lock file with exactly that uv binary.
- Emits a warning, skips alignment, and completes the lock update with the
  uv on `PATH` when Dependabot's uv version cannot be determined. The next
  run self-corrects.

A week where the pin already accepts Dependabot's uv changes nothing. A
repository without a pin gets a notice and no other change.

```yaml
      - uses: mongodb-labs/drivers-github-tools/python/uv-lock-update@v3
        with:
          app_id: ${{ vars.APP_ID }}
          private_key: ${{ secrets.APP_PRIVATE_KEY }}
          track_dependabot_uv: true
```

The action sets no resolution cutoff. A repo that wants to hold back newly
published packages configures `exclude-newer` in its own `pyproject.toml` or
`uv.toml`, exactly as for `python/setup`.
