# Contributing to this repository

This repository provides shared GitHub Actions for MongoDB drivers.

Opinionated actions for each driver should go in their own folder.

## Linting

This repo uses [pre-commit](https://pypi.org/project/pre-commit/) for managing linting. `pre-commit` performs various
checks on the files and uses tools that help follow a consistent style within the repo.

To set up `pre-commit` locally, run:

```bash
brew install pre-commit
pre-commit install
```

To run `pre-commit` manually, run `pre-commit run --all-files`.

To run a manual hook like `shellcheck` manually, run:

```bash
pre-commit run --all-files --hook-stage manual shellcheck
```

## Version Tag

To cut a release, run the [Release workflow](https://github.com/mongodb-labs/drivers-github-tools/actions/workflows/release.yml)
with the desired `bump` input (`patch`, `minor`, or `major`). Use `dry_run: true` first to preview
the computed version before pushing anything.

A `major` bump also updates `.github/workflows/version.txt` automatically. Internal
action-to-action references use `$/` and do not need updating on a version bump.
Update the example `mongodb-labs/drivers-github-tools/...@vX` references in
`README.md` and `node/release_template.yml`, both of which document or use the
tag external consumers should pin to — this remains a manual step after a major bump.

Before the first `vX.Y.Z` tag exists, the workflow bootstraps from the current floating
major tag (e.g. `v3` becomes `v3.0.0`) and ignores the requested `bump` input for that one
run — don't be surprised if a first-time `major`/`minor` bump doesn't change the version the
way you'd expect. Every release after that first one bumps normally from the latest `vX.Y.Z`
tag.