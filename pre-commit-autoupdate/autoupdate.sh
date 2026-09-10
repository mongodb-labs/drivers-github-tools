#!/usr/bin/env bash
# Apply the cooldown to the freshly updated config, summarize what is left,
# commit it to the bot owned branch, push, and report the summary back as step
# outputs. action.yml passes those to $/open-or-update-pr, which opens or
# refreshes the pull request.
#
# Sets two outputs: `changed`, which gates that step, and `body`, the pull
# request body.
#
# Required environment: GH_TOKEN, BRANCH, DRY_RUN, OLD_CONFIG, CONFIG_PATH,
# COOLDOWN_DAYS, ACTION_PATH, and GITHUB_OUTPUT plus GITHUB_REPOSITORY from the
# Actions runtime.
set -euo pipefail

# Write a step output whose value may span lines. A random delimiter keeps a
# value that happens to contain the delimiter text from closing the heredoc
# early, which would let the rest of the value be parsed as further outputs.
emit_output() {
  local name="$1"
  local value="$2"
  local delim
  delim="EOF_$(openssl rand -hex 16)"
  {
    echo "${name}<<${delim}"
    echo "$value"
    echo "$delim"
  } >> "$GITHUB_OUTPUT"
}

no_changes() {
  echo "$1"
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
}

# Compare against the copy taken before the update, which is the same baseline
# the summary below is built from. `git diff` would compare against HEAD
# instead, so a workspace that was already dirty would disagree with the summary
# and could open a pull request whose body reports no hook changes.
if cmp -s "$OLD_CONFIG" "$CONFIG_PATH"; then
  no_changes "No changes detected, skipping PR creation"
fi

# Reverts any rev whose release is still inside the cooldown, and prints a
# markdown bullet for each one it held. Runs before the summary so the pull
# request describes the revs it actually carries.
HELD=$(python3 "$ACTION_PATH/apply_cooldown.py" "$OLD_CONFIG" "$CONFIG_PATH" "$COOLDOWN_DAYS")

# The cooldown can revert every proposed update, which puts the config back
# exactly where it started. Re-checking here is what keeps that case from
# opening a pull request with an empty diff.
if cmp -s "$OLD_CONFIG" "$CONFIG_PATH"; then
  no_changes "Every update was held back by the cooldown, skipping PR creation"
fi

UPDATES=$(python3 "$ACTION_PATH/diff_config.py" "$OLD_CONFIG" "$CONFIG_PATH")

if [ -n "$UPDATES" ]; then
  BODY="## Updated hooks"$'\n\n'"${UPDATES}"
else
  BODY="No hook revision changes. The configuration changed; see the file diff for details."
fi

# Listing what was held tells a reviewer the run was not simply quiet, and names
# what to expect next week.
if [ -n "$HELD" ]; then
  BODY="${BODY}"$'\n\n'"## Held back by the cooldown"$'\n\n'"${HELD}"
fi

# Everything below mutates state, so a dry run skips all of it and leaves the
# workspace untouched. The pull request step still runs and still reports the
# decision: it finds an existing pull request by querying the remote for the head
# branch, so it needs no local branch or commit.
if [ "$DRY_RUN" != "true" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git checkout -B "$BRANCH"
  git add "$CONFIG_PATH"
  git commit -m "Update pre-commit hooks"

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

echo "changed=true" >> "$GITHUB_OUTPUT"
emit_output body "$BODY"
