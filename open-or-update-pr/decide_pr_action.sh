#!/usr/bin/env bash
# Decide whether to open a new PR or refresh the existing open one on the same
# branch. An open PR already on $BRANCH is updated in place. A merged or
# manually closed PR is not "open", so this falls through to creating a fresh
# one, with no extra state to track.
#
# Required environment: BRANCH, BASE, TITLE, BODY, LABELS, DRY_RUN, and
# GH_TOKEN plus GH_REPO for gh itself.
set -euo pipefail

# Deliberately no --base filter here: if a reviewer retargets the open PR to
# a different base, this query must still find it by head branch alone, or
# the next run falls through to `gh pr create` and GitHub allows a second
# open PR from the same force-pushed branch. New PRs still target $BASE below.
# --head matches on branch name only, and gh has no --owner filter, so a fork
# with a branch of the same name could otherwise match and we would edit someone
# else's pull request. isCrossRepository excludes anything not from this repo.
PR_NUMBER=$(gh pr list --head "$BRANCH" --state open --json number,isCrossRepository --jq 'map(select(.isCrossRepository == false)) | .[0].number // empty')

if [ "$DRY_RUN" = "true" ]; then
  # `gh pr create --dry-run` documents that it "may still push git changes",
  # so a dry run reports the decision and never reaches a mutating gh command.
  # The listing above is read only and safe.
  if [ -n "$PR_NUMBER" ]; then
    echo "Would update PR #$PR_NUMBER on $BRANCH"
  else
    echo "Would create PR \"$TITLE\" from $BRANCH into $BASE"
  fi
  # Log the body too, so a dry run verifies the generated summary and not just
  # the create-or-update decision.
  echo "::group::Pull request body"
  echo "$BODY"
  echo "::endgroup::"
  exit 0
fi

# gh rejects an empty --label/--add-label value, so omit the flag entirely when
# no labels were requested rather than passing "" through. The ${arr[@]+...}
# form expands to nothing for an empty array instead of tripping `set -u` on
# bash 3.2, which is what a contributor on macOS runs the tests with.
EDIT_LABEL_ARGS=()
CREATE_LABEL_ARGS=()
if [ -n "$LABELS" ]; then
  EDIT_LABEL_ARGS=(--add-label "$LABELS")
  CREATE_LABEL_ARGS=(--label "$LABELS")
fi

if [ -n "$PR_NUMBER" ]; then
  gh pr edit "$PR_NUMBER" --body "$BODY" ${EDIT_LABEL_ARGS[@]+"${EDIT_LABEL_ARGS[@]}"}
  echo "Updated PR #$PR_NUMBER"
else
  gh pr create \
    --title "$TITLE" \
    --body "$BODY" \
    --base "$BASE" \
    ${CREATE_LABEL_ARGS[@]+"${CREATE_LABEL_ARGS[@]}"} \
    --head "$BRANCH"
fi
