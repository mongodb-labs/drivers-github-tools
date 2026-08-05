#!/usr/bin/env bash
# Summarize the upgraded lock file, commit it to the bot owned branch, push, and
# hand off to decide_pr_action.sh to open or refresh the pull request.
#
# Required environment: GH_TOKEN, BRANCH, BASE, LABELS, DRY_RUN, OLD_LOCK,
# ACTION_PATH, and GITHUB_REPOSITORY from the Actions runtime.
set -euo pipefail

# Compare against the copy taken before the upgrade, which is the same baseline
# diff_lock.py summarizes from. `git diff` would compare against HEAD instead, so
# a workspace that was already dirty would disagree with the summary and could
# open a pull request whose body reports no version changes.
if cmp -s "$OLD_LOCK" uv.lock; then
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

# Everything below mutates state, so a dry run skips all of it and leaves the
# workspace untouched. decide_pr_action.sh still runs and still reports the
# decision: it finds an existing pull request by querying the remote for the head
# branch, so it needs no local branch or commit.
if [ "$DRY_RUN" != "true" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git checkout -B "$BRANCH"
  git add uv.lock
  git commit -m "Update uv.lock"

  # The branch is exclusively bot owned and rebuilt fresh from the checked-out
  # ref every run, so overwriting whatever is currently on the remote (a
  # still-open PR's branch, a stale closed-PR branch, or nothing) is always safe
  # and always correct.
  # Supply credentials through a helper that reads GH_TOKEN from the
  # environment, so the token is never written to .git/config, never embedded in
  # the remote URL where git error output could echo it, and never passed as a
  # command argument. The empty first -c clears any inherited helper.
  git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && echo username=x-access-token && echo "password=$GH_TOKEN"; }; f' \
    push --force "https://github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
fi

BRANCH="$BRANCH" BASE="$BASE" TITLE="Automation: Update uv.lock" \
BODY="$BODY" LABELS="$LABELS" DRY_RUN="$DRY_RUN" \
  bash "$ACTION_PATH/decide_pr_action.sh"
