#!/usr/bin/env bash
# Open a new PR, or refresh the one already open on $BRANCH.
set -euo pipefail

PR_NUMBER=$(gh pr list --head "$BRANCH" --state open --json number,isCrossRepository --jq 'map(select(.isCrossRepository == false)) | .[0].number // empty')

if [ "$DRY_RUN" = "true" ]; then
  # `gh pr create --dry-run` documents that it "may still push git changes",
  # so the dry run is hand-rolled here instead.
  if [ -n "$PR_NUMBER" ]; then
    echo "Would update PR #$PR_NUMBER on $BRANCH"
  else
    echo "Would create PR \"$TITLE\" from $BRANCH into $BASE"
  fi
  echo "::group::Pull request body"
  echo "$BODY"
  echo "::endgroup::"
  exit 0
fi

# gh rejects an empty --label value, so omit the flag rather than pass "".
# The ${arr[@]+...} form expands to nothing for an empty array instead of
# tripping `set -u` on bash 3.2, which is what macOS ships.
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
