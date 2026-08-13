#!/usr/bin/env bash
# Run `just install` when the project defines that recipe, and skip cleanly when
# it does not. Consumers that only want uv and just on PATH — or that have no
# justfile at all — get a no-op rather than a failure, so the same action serves
# both without the caller having to know which case it is in.
set -euo pipefail

# `just --summary` prints the recipe names on one space-separated line and exits
# non-zero only when there is no justfile to read. A justfile with no recipes
# exits 0 with empty output, so it falls through to the recipe check below.
if ! SUMMARY=$(just --summary 2>/dev/null); then
  echo "Skipping 'just install': no justfile found."
  exit 0
fi

# Split to one name per line and match whole lines. Substring matching would fire
# on `install-deps`, `preinstall`, and `uninstall` — and `grep -w` is no help,
# because it counts `-` as a word boundary and so still matches `install-deps`.
if ! echo "$SUMMARY" | tr ' ' '\n' | grep -qx 'install'; then
  echo "Skipping 'just install': no 'install' recipe in the justfile."
  exit 0
fi

just install
