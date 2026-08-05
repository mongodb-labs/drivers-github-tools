#!/usr/bin/env bash
# Summarize the upgraded lock file, commit it to the bot owned branch, push, and
# hand off to decide_pr_action.sh to open or refresh the pull request.
#
# Required environment: GH_TOKEN, BRANCH, BASE, LABELS, DRY_RUN, OLD_LOCK,
# ACTION_PATH, and GITHUB_REPOSITORY from the Actions runtime.
set -euo pipefail

if git diff --quiet uv.lock; then
  echo "No changes detected, skipping PR creation"
  exit 0
fi

# diff_lock.py needs tomllib, so Python 3.11 or newer. uv is already a
# requirement of this action, so let it supply a suitable interpreter rather
# than depending on whatever the runner's python3 happens to be.
UPDATES=$(uv run --no-project --python '>=3.11' python "$ACTION_PATH/diff_lock.py" "$OLD_LOCK" uv.lock)

if [ -n "$UPDATES" ]; then
  BODY="## Updated packages"$'\n\n'"${UPDATES}"
else
  BODY="No package version changes. The lock file metadata changed; see the file diff for details."
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git checkout -B "$BRANCH"
git add uv.lock
git commit -m "Update uv.lock"

# The branch is exclusively bot owned and rebuilt fresh from the checked-out ref
# every run, so overwriting whatever is currently on the remote (a still-open
# PR's branch, a stale closed-PR branch, or nothing) is always safe and always
# correct.
# Authenticate the push inline rather than with `git remote set-url`, so the
# token is never written to the workspace .git/config.
if [ "$DRY_RUN" != "true" ]; then
  git push --force "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
fi

BRANCH="$BRANCH" BASE="$BASE" TITLE="Automation: Update uv.lock" \
BODY="$BODY" LABELS="$LABELS" DRY_RUN="$DRY_RUN" \
  bash "$ACTION_PATH/decide_pr_action.sh"
