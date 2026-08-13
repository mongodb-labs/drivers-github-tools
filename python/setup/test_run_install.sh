#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/run_install.sh"
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=1
  fi
}

check_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "OK: $desc"
  else
    echo "FAIL: $desc"
    echo "  expected to find: $needle"
    echo "  in: $haystack"
    FAIL=1
  fi
}

# Each case runs in its own directory. `just` walks up to find a justfile, so the
# "no justfile" case needs a tree with none above it: TMPDIR is under the system
# temp dir, not the repo.
run_script() {
  local case_name="$1"
  local justfile_body="${2-}"
  WORKDIR="$TMPDIR/$case_name"
  mkdir -p "$WORKDIR"
  if [ -n "$justfile_body" ]; then
    printf '%s' "$justfile_body" > "$WORKDIR/justfile"
  fi
  STATUS=0
  OUTPUT=$(cd "$WORKDIR" && bash "$SCRIPT" 2>&1) || STATUS=$?
}

ran_marker() { [ -f "$WORKDIR/ran" ] && echo "ran" || echo "did not run"; }

# The whole point of the action's optional install step: a project that defines
# `install` gets it run.
run_script "has-install" 'install:
	@touch ran
'
check "install recipe: exit status is 0" "0" "$STATUS"
check "install recipe: it is run" "ran" "$(ran_marker)"

# A recipe named `install-deps` contains "install" as a prefix. `grep -w` treats
# `-` as a word boundary and would match it, running the wrong recipe name (or
# failing outright). Matching must be on the whole recipe name.
run_script "install-prefix" 'install-deps:
	@touch ran
'
check "install-deps only: exit status is 0" "0" "$STATUS"
check "install-deps only: nothing is run" "did not run" "$(ran_marker)"
check_contains "install-deps only: the skip is reported" "no 'install' recipe" "$OUTPUT"

# The same substring trap from the other side: `uninstall` and `preinstall` both
# contain "install" and must not be mistaken for it.
run_script "install-substrings" 'uninstall:
	@touch ran

preinstall:
	@touch ran
'
check "uninstall/preinstall only: exit status is 0" "0" "$STATUS"
check "uninstall/preinstall only: nothing is run" "did not run" "$(ran_marker)"

# A repo with no justfile at all must be a clean skip, not a failure: this is the
# case for consumers that use the action purely to get uv and just on PATH.
run_script "no-justfile"
check "no justfile: exit status is 0" "0" "$STATUS"
check_contains "no justfile: the skip is reported" "no justfile" "$OUTPUT"

# A justfile with recipes but no `install` is a skip, and one with no recipes at
# all must not trip the "no justfile" path either.
run_script "no-recipes" '# a justfile with only a comment
'
check "justfile with no recipes: exit status is 0" "0" "$STATUS"
check_contains "justfile with no recipes: the skip is reported" "no 'install' recipe" "$OUTPUT"

# A failing install must fail the job. Swallowing it would let CI proceed with
# missing dependencies and report a confusing downstream error instead.
run_script "failing-install" 'install:
	@exit 3
'
check "failing install recipe: the failure propagates" "3" "$STATUS"

exit $FAIL
