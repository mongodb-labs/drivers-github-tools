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

To bump the version tag, run the "Update Tag" [workflow](https://github.com/mongodb-labs/drivers-github-tools/actions/workflows/update-action-tag.yml).

To change the major version, update `.github/workflows/version.txt`. Internal
action-to-action references use `$/` and do not need updating on a version bump.
Update the example `mongodb-labs/drivers-github-tools/...@vX` references in
`README.md` and `node/release_template.yml`, both of which document or use the
tag external consumers should pin to.