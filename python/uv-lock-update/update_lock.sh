#!/usr/bin/env bash
# Summarize the upgraded lock file, commit it to the bot owned branch, push,
# and report the summary as step outputs. action.yml gates
# $/open-or-update-pr on `changed`. ALIGNED=true adds the rewritten
# required-version (OLD_PIN to NEW_PIN) to the same commit and pull request.
set -euo pipefail

# Write a step output that may span lines. A random delimiter stops a value
# containing the delimiter text from closing the heredoc early, which would let
# the rest parse as further outputs.
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

# Compare against the copy taken before the upgrade, the same baseline
# diff_lock.py uses. `git diff` compares against HEAD, so an already dirty
# workspace could open a pull request whose body reports no changes.
# The aligned pin rides in the same pull request: a pin-only week opens one too.
if cmp -s "$OLD_LOCK" uv.lock && [ "${ALIGNED:-false}" != "true" ]; then
  echo "No changes detected, skipping PR creation"
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# diff_lock.py needs tomllib, so Python 3.11+. Run it through UV_BIN
# (Dependabot's uv) when set, else the uv on PATH.
UV=(uv)
if [ -n "${UV_BIN:-}" ]; then
  UV=("$UV_BIN")
fi
UPDATES=$("${UV[@]}" run --no-project --python '>=3.11' python "$ACTION_PATH/diff_lock.py" "$OLD_LOCK" uv.lock)

BODY=""
if [ "${ALIGNED:-false}" = "true" ]; then
  BODY="## uv version alignment"$'\n\n'
  BODY+="\`required-version\` updated: \`${OLD_PIN}\` → \`${NEW_PIN}\`, tracking the uv in Dependabot's latest updater image (uv ${DEPENDABOT_UV}); the lock file below was regenerated with that same uv."
fi

if [ -n "$UPDATES" ]; then
  [ -n "$BODY" ] && BODY+=$'\n\n'
  BODY+="## Updated packages"$'\n\n'"${UPDATES}"
elif [ -n "$BODY" ]; then
  if cmp -s "$OLD_LOCK" uv.lock; then
    BODY+=$'\n\n'"No package version changes; the lock file itself is unchanged."
  else
    BODY+=$'\n\n'"No package version changes. The lock file metadata changed; see the file diff for details."
  fi
else
  BODY="No package version changes. The lock file metadata changed; see the file diff for details."
fi

# Everything below mutates state, so a dry run skips it and leaves the
# workspace untouched. The pull request step still reports its decision: it
# queries the remote for the head branch, needing no local branch or commit.
if [ "$DRY_RUN" != "true" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git checkout -B "$BRANCH"
  git add uv.lock
  COMMIT_MSG="Update uv.lock"
  if [ "${ALIGNED:-false}" = "true" ]; then
    git add pyproject.toml
    COMMIT_MSG="Update uv.lock and track Dependabot uv ${DEPENDABOT_UV}"
  fi
  git commit -m "$COMMIT_MSG"

  # Credentials come from a helper reading GH_TOKEN from the environment, so
  # the token never lands in .git/config, the remote URL, or an argument. The
  # empty first -c clears any inherited helper.
  git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && echo username=x-access-token && echo "password=$GH_TOKEN"; }; f' \
    push --force "https://github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
fi

echo "changed=true" >> "$GITHUB_OUTPUT"
emit_output body "$BODY"
