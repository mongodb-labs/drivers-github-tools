#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/update_lock.sh"
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

# update_lock.sh reaches diff_lock.py through $ACTION_PATH, so pointing that at a
# stub isolates its own orchestration from the real diff.
STUB="$TMPDIR/action"
mkdir -p "$STUB"
printf 'print("- demo: `1.0` -> `2.0`")\n' > "$STUB/diff_lock.py"

# A repo whose uv.lock differs from HEAD, so the "no changes" early exit is not
# taken and the script runs its full body.
REPO="$TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf 'old\n' > "$REPO/uv.lock"
git -C "$REPO" add uv.lock
git -C "$REPO" commit -qm init
printf 'new\n' > "$REPO/uv.lock"
printf 'old\n' > "$TMPDIR/uv.lock.before"

# Read a step output back out of a $GITHUB_OUTPUT file, resolving the heredoc
# form update_lock.sh writes multi-line values with. Parsing it the way Actions
# does is what proves the delimiter framing is well formed.
read_output() {
  local file="$1"
  local name="$2"
  awk -v key="$name" '
    !in_block && $0 ~ "^" key "<<" { delim = substr($0, length(key) + 3); in_block = 1; next }
    !in_block && index($0, key "=") == 1 { print substr($0, length(key) + 2); found = 1; next }
    in_block && $0 == delim { in_block = 0; next }
    in_block { print }
  ' "$file"
}

# Every variable update_lock.sh documents as required on the dry-run path.
# GH_TOKEN, GITHUB_REPOSITORY, and BRANCH are deliberately absent: they are
# referenced only by the commit and push, which a dry run skips.
run_update() {
  local skip="${1:-}"
  : > "$TMPDIR/github_output"
  (
    cd "$REPO" || exit 1
    export DRY_RUN=true
    export OLD_LOCK="$TMPDIR/uv.lock.before"
    export ACTION_PATH="$STUB"
    export GITHUB_OUTPUT="$TMPDIR/github_output"
    # Unset after exporting, so the variable is genuinely absent rather than
    # being reassigned by a later argument on the same command.
    if [ -n "$skip" ]; then
      unset "$skip"
    fi
    bash "$SCRIPT"
  ) > "$TMPDIR/out.log" 2>&1
}

# A dry run reports the values the action promises, and leaves the repo alone.
set +e
run_update
STATUS=$?
set -e

check "dry run succeeds" "0" "$STATUS"
check "a change is reported, so the pull request step runs" \
  "true" "$(read_output "$TMPDIR/github_output" changed)"
check "body starts with the summary heading" \
  "## Updated packages" \
  "$(read_output "$TMPDIR/github_output" body | head -1)"
check "body carries the diff output" \
  '- demo: `1.0` -> `2.0`' \
  "$(read_output "$TMPDIR/github_output" body | tail -1)"

check "dry run creates no commit" "1" "$(git -C "$REPO" rev-list --count HEAD)"
check "dry run leaves the branch alone" \
  "" \
  "$(git -C "$REPO" branch --list uv-lock-update)"

# Change detection compares against the pre-upgrade copy, not against HEAD. A
# workspace that was already dirty must still count as "no change" when the
# upgrade produced nothing, or the pull request body would report no version
# changes while claiming there were some.
printf 'new\n' > "$TMPDIR/uv.lock.unchanged"
: > "$TMPDIR/nochange_output"
set +e
(
  cd "$REPO" || exit 1
  export DRY_RUN=true
  export OLD_LOCK="$TMPDIR/uv.lock.unchanged" ACTION_PATH="$STUB"
  export GITHUB_OUTPUT="$TMPDIR/nochange_output"
  bash "$SCRIPT"
) > "$TMPDIR/nochange.log" 2>&1
STATUS=$?
set -e

check "dirty workspace with an unchanged lock exits cleanly" "0" "$STATUS"
check "dirty workspace with an unchanged lock reports no changes" \
  "No changes detected, skipping PR creation" \
  "$(cat "$TMPDIR/nochange.log")"
# The gate must be reported explicitly. An absent output would also skip the
# pull request step, but only because Actions treats it as empty, so asserting
# the literal value keeps that from passing by accident.
check "no changes gates the pull request step off" \
  "false" "$(read_output "$TMPDIR/nochange_output" changed)"
check "no changes emits no body" \
  "" "$(read_output "$TMPDIR/nochange_output" body)"

# Each documented variable is genuinely required: unset it and the script fails
# rather than proceeding with an empty value.
for VAR in DRY_RUN OLD_LOCK ACTION_PATH GITHUB_OUTPUT; do
  set +e
  run_update "$VAR"
  STATUS=$?
  set -e
  check "missing $VAR fails the run" "1" "$([ "$STATUS" -ne 0 ] && echo 1 || echo 0)"
done

# A git stub intercepts push so the non-dry path runs here; the intercepted
# pushes are logged for assertion.
BIN="$TMPDIR/bin"
mkdir -p "$BIN"
PUSHES="$TMPDIR/pushes.log"
REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<STUB
#!/usr/bin/env bash
# The first argument that is neither an -c flag nor its value is the subcommand.
skip_next=0
for arg in "\$@"; do
  if [ "\$skip_next" = 1 ]; then skip_next=0; continue; fi
  case "\$arg" in
    -c) skip_next=1 ;;
    *) first="\$arg"; break ;;
  esac
done
if [ "\${first:-}" = push ]; then
  echo "\$*" >> "$PUSHES"
  exit 0
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$BIN/git"

# A committed pyproject.toml whose simulated pin satisfies whatever uv runs
# this harness; align_uv_pin.py's own rewrites live in test_align_uv_pin.sh.
cat > "$REPO/pyproject.toml" <<'EOF'
[tool.uv]
# Pin the uv binary version across local dev, GitHub Actions, and Evergreen.
required-version = "==0.12.12"
EOF
git -C "$REPO" add pyproject.toml
git -C "$REPO" commit -qm pin
sed -i 's/==0.12.12/>=0.9,<99/' "$REPO/pyproject.toml"

# A uv stub for UV_BIN: logs its call and passes the inner python to the
# real interpreter, so the fake diff_lock.py keeps serving the diff.
UV_CALLS="$TMPDIR/uv_calls.log"
cat > "$BIN/uv" <<STUB
#!/usr/bin/env bash
echo "uv \$*" >> "$UV_CALLS"
while [ "\$#" -gt 0 ] && [ "\$1" != python ]; do shift; done
if [ "\$#" -eq 0 ]; then
  echo "uv stub: not a python invocation" >&2
  exit 1
fi
shift
exec "\$(command -v python3)" "\$@"
STUB
chmod +x "$BIN/uv"

# A pin-only week still opens its pull request, alignment first in the body.
printf 'new\n' > "$TMPDIR/uv.lock.matching"
: > "$TMPDIR/aligned_output"
set +e
(
  cd "$REPO" || exit 1
  export DRY_RUN=true
  export OLD_LOCK="$TMPDIR/uv.lock.matching" ACTION_PATH="$STUB"
  export GITHUB_OUTPUT="$TMPDIR/aligned_output"
  export ALIGNED=true OLD_PIN='==0.12.12' NEW_PIN='>=0.13.7,<0.14' DEPENDABOT_UV=0.13.7
  bash "$SCRIPT"
) > "$TMPDIR/aligned.log" 2>&1
STATUS=$?
set -e

check "pin-only change succeeds" "0" "$STATUS"
check "pin-only change still opens the pull request" \
  "true" "$(read_output "$TMPDIR/aligned_output" changed)"
check "alignment leads the pull request body" \
  "## uv version alignment" \
  "$(read_output "$TMPDIR/aligned_output" body | head -1)"
check "body reports the old and new pins" \
  "1" \
  "$(read_output "$TMPDIR/aligned_output" body | grep -c '`==0.12.12` → `>=0.13.7,<0.14`' || true)"
check "pin-only dry run creates no commit" \
  "2" "$(git -C "$REPO" rev-list --count HEAD)"

# When UV_BIN is set, the diff runs through it, not the uv on PATH.
: > "$UV_CALLS"
: > "$TMPDIR/uvbin_output"
set +e
(
  cd "$REPO" || exit 1
  export DRY_RUN=true
  export OLD_LOCK="$TMPDIR/uv.lock.before" ACTION_PATH="$STUB"
  export GITHUB_OUTPUT="$TMPDIR/uvbin_output"
  export UV_BIN="$BIN/uv"
  bash "$SCRIPT"
) > "$TMPDIR/uvbin.log" 2>&1
STATUS=$?
set -e

check "UV_BIN run succeeds" "0" "$STATUS"
check "diff ran through the installed uv, not the one on PATH" \
  "1" "$(grep -c 'run --no-project --python >=3.11 python' "$UV_CALLS" || true)"
check "UV_BIN run reports the change" \
  "true" "$(read_output "$TMPDIR/uvbin_output" changed)"
check "UV_BIN run keeps the plain body" \
  "## Updated packages" \
  "$(read_output "$TMPDIR/uvbin_output" body | head -1)"
unset UV_BIN

# The production path: the aligned pin and the lock commit and push together.
: > "$PUSHES"
set +e
(
  cd "$REPO" || exit 1
  export OLD_LOCK="$TMPDIR/uv.lock.before" ACTION_PATH="$STUB"
  export GITHUB_OUTPUT="$TMPDIR/nondry_output"
  export BRANCH=uv-lock-update GITHUB_REPOSITORY=example/org GH_TOKEN=test-token
  export ALIGNED=true OLD_PIN='==0.12.12' NEW_PIN='>=0.13.7,<0.14' DEPENDABOT_UV=0.13.7
  export DRY_RUN=false
  # Production hands over the installed uv whenever it aligned the pin.
  export UV_BIN="$BIN/uv"
  PATH="$BIN:$PATH" bash "$SCRIPT"
) > "$TMPDIR/nondry.log" 2>&1
STATUS=$?
set -e

check "non-dry aligned run succeeds" "0" "$STATUS"
check "non-dry aligned run reports the change" \
  "true" "$(read_output "$TMPDIR/nondry_output" changed)"
check "aligned commit lands on the bot branch" \
  "3" "$(git -C "$REPO" rev-list --count HEAD)"
check "commit message names the tracked uv" \
  "Update uv.lock and track Dependabot uv 0.13.7" \
  "$(git -C "$REPO" log -1 --format=%s)"
check "commit carries the pin and the lock" \
  "pyproject.toml uv.lock" \
  "$(git -C "$REPO" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
check "push reached the bot branch" \
  "1" "$(grep -c 'push --force https://github.com/example/org.git uv-lock-update' "$PUSHES" || true)"

# Without alignment, the commit keeps the original message and the lock only.
printf 'newer\n' > "$REPO/uv.lock"
: > "$PUSHES"
set +e
(
  cd "$REPO" || exit 1
  export OLD_LOCK="$TMPDIR/uv.lock.before" ACTION_PATH="$STUB"
  export GITHUB_OUTPUT="$TMPDIR/plain_output"
  export BRANCH=uv-lock-update GITHUB_REPOSITORY=example/org GH_TOKEN=test-token
  export DRY_RUN=false
  unset ALIGNED OLD_PIN NEW_PIN DEPENDABOT_UV UV_BIN
  PATH="$BIN:$PATH" bash "$SCRIPT"
) > "$TMPDIR/plain.log" 2>&1
STATUS=$?
set -e

check "non-dry unaligned run succeeds" "0" "$STATUS"
check "unaligned commit keeps the original message" \
  "Update uv.lock" \
  "$(git -C "$REPO" log -1 --format=%s)"
check "unaligned commit carries the lock only" \
  "uv.lock" \
  "$(git -C "$REPO" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"

exit $FAIL
