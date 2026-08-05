#!/usr/bin/env bash
# Decide whether to open a new lock-update PR or refresh the existing open one
# on the same branch. An open PR already on $BRANCH is updated in place. A
# merged or manually closed PR is not "open", so this falls through to creating
# a fresh one, with no extra state to track.
#
# Required environment: BRANCH, BASE, TITLE, BODY, LABELS, DRY_RUN
set -euo pipefail

# Deliberately no --base filter here: if a reviewer retargets the open PR to
# a different base, this query must still find it by head branch alone, or
# the next run falls through to `gh pr create` and GitHub allows a second
# open PR from the same force-pushed branch. New PRs still target $BASE below.
PR_NUMBER=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')

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

if [ -n "$PR_NUMBER" ]; then
  gh pr edit "$PR_NUMBER" --body "$BODY" --add-label "$LABELS"
  echo "Updated PR #$PR_NUMBER"
else
  gh pr create \
    --title "$TITLE" \
    --body "$BODY" \
    --base "$BASE" \
    --label "$LABELS" \
    --head "$BRANCH"
fi
