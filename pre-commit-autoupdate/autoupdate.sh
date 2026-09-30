#!/usr/bin/env bash
# Summarize the updated hook revisions, commit them to the bot owned branch,
# push, and report the summary as step outputs. action.yml gates
# $/open-or-update-pr on `changed`.
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

no_changes() {
  echo "$1"
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
}

# Compare against the copy taken before the update. `git diff` compares
# against HEAD, so an already dirty workspace could open a pull request whose
# body reports no hook changes.
if cmp -s "$OLD_CONFIG" "$CONFIG_PATH"; then
  no_changes "No changes detected, skipping PR creation"
fi

# `prek update` rewrites only the rev lines, so a diff of those is the summary.
# `diff` exits 1 when files differ, so `|| true` keeps pipefail from ending it.
UPDATES=$({ diff "$OLD_CONFIG" "$CONFIG_PATH" || true; } | sed -n 's/^> *rev: *\(.*\)/- `\1`/p')

if [ -n "$UPDATES" ]; then
  BODY="## Updated hooks"$'\n\n'"${UPDATES}"
else
  BODY="No hook revision changes. The configuration changed; see the file diff for details."
fi

# A dry run skips the mutations below. The pull request step still reports its
# decision: it queries the remote, needing no local branch or commit.
if [ "$DRY_RUN" != "true" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git checkout -B "$BRANCH"
  git add "$CONFIG_PATH"
  git commit -m "Update pre-commit hooks"

  # Credentials come from a helper reading GH_TOKEN from the environment, so
  # the token never lands in .git/config, the remote URL, or an argument. The
  # empty first -c clears any inherited helper.
  git -c credential.helper= \
    -c 'credential.helper=!f() { test "$1" = get && echo username=x-access-token && echo "password=$GH_TOKEN"; }; f' \
    push --force "https://github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"
fi

echo "changed=true" >> "$GITHUB_OUTPUT"
emit_output body "$BODY"
