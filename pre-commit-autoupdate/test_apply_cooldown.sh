#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/apply_cooldown.py"
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

NOW=$(date +%s)
DAY=86400

# A real hook repo with real tags, served over file://, so the tag dating goes
# through the same git fetch the action uses against a remote host. Stubbing it
# out would leave the part most likely to be wrong untested. file:// rather than
# a bare path because git ignores --depth on a local-path clone.
HOOK_REPO="$TMPDIR/hook-repo"
mkdir -p "$HOOK_REPO"
git -C "$HOOK_REPO" init -q
git -C "$HOOK_REPO" config user.email test@example.com
git -C "$HOOK_REPO" config user.name test
echo hook > "$HOOK_REPO/hook.py"
git -C "$HOOK_REPO" add hook.py
GIT_AUTHOR_DATE="@$((NOW - 400 * DAY)) +0000" \
GIT_COMMITTER_DATE="@$((NOW - 400 * DAY)) +0000" \
  git -C "$HOOK_REPO" commit -qm init

# An annotated tag takes its date from GIT_COMMITTER_DATE, which is what
# %(taggerdate) reads back.
tag_at() {
  local name="$1"
  local days_ago="$2"
  GIT_COMMITTER_DATE="@$((NOW - days_ago * DAY)) +0000" \
    git -C "$HOOK_REPO" tag -a -m "release $name" "$name" HEAD
}

tag_at v1.0.0 200
tag_at v2.0.0 1
tag_at v3.0.0 30
# A lightweight tag carries no tagger date, so the committer date is the only
# date available for it.
git -C "$HOOK_REPO" tag v-lightweight HEAD

HOOK_URL="file://$HOOK_REPO"

write_configs() {
  local old_rev="$1"
  local new_rev="$2"
  cat > "$TMPDIR/old.yaml" <<EOF
repos:
- repo: $HOOK_URL
  rev: $old_rev
  hooks:
  - id: demo
EOF
  cat > "$TMPDIR/new.yaml" <<EOF
repos:
- repo: $HOOK_URL
  rev: $new_rev
  hooks:
  - id: demo
EOF
}

run_cooldown() {
  local cooldown="$1"
  set +e
  python3 "$SCRIPT" "$TMPDIR/old.yaml" "$TMPDIR/new.yaml" "$cooldown" \
    > "$TMPDIR/held.log" 2> "$TMPDIR/notices.log"
  STATUS=$?
  set -e
}

current_rev() {
  sed -n 's/^  rev: //p' "$TMPDIR/new.yaml"
}

# A release well past the cooldown is adopted, and nothing is reported as held.
write_configs v1.0.0 v3.0.0
run_cooldown 7
check "an aged release is adopted" "v3.0.0" "$(current_rev)"
check "an aged release is not reported as held" "" "$(cat "$TMPDIR/held.log")"
check "an aged release exits cleanly" "0" "$STATUS"

# A release inside the cooldown is reverted to the rev that was there before, so
# the config keeps a version that has had time to be yanked.
write_configs v1.0.0 v2.0.0
run_cooldown 7
check "a fresh release is reverted to the previous rev" "v1.0.0" "$(current_rev)"
check_contains "a fresh release is reported as held" "held \`v2.0.0\`" "$(cat "$TMPDIR/held.log")"
check_contains "a fresh release is reported with its age" "released 1d ago" "$(cat "$TMPDIR/held.log")"
check_contains "a fresh release emits a workflow notice" "::notice::" "$(cat "$TMPDIR/notices.log")"

# The cutoff is the cooldown, not a fixed week: the same release passes once the
# window is short enough to admit it.
write_configs v1.0.0 v2.0.0
run_cooldown 0.5
check "a release older than a shorter cooldown is adopted" "v2.0.0" "$(current_rev)"

# Zero disables the cooldown entirely, which is the documented escape hatch.
write_configs v1.0.0 v2.0.0
run_cooldown 0
check "cooldown 0 adopts the newest release" "v2.0.0" "$(current_rev)"

# A rev whose age cannot be established must not be assumed safe. Holding is the
# conservative direction, and the warning keeps it visible.
write_configs v1.0.0 v9.9.9-does-not-exist
run_cooldown 7
check "an undatable rev is held" "v1.0.0" "$(current_rev)"
check_contains "an undatable rev warns rather than failing silently" \
  "::warning::" "$(cat "$TMPDIR/notices.log")"
check_contains "an undatable rev is reported as held" \
  "release date unknown" "$(cat "$TMPDIR/held.log")"

# A lightweight tag has no tagger date. Falling back to the commit date is what
# keeps it from being treated as undatable and held forever.
write_configs v1.0.0 v-lightweight
run_cooldown 7
check "a lightweight tag is dated from its commit and adopted" \
  "v-lightweight" "$(current_rev)"

# Each repo is judged on its own release, so one held hook does not block the
# rest of the update.
SECOND_URL="file://$TMPDIR/hook-repo"
cat > "$TMPDIR/old.yaml" <<EOF
repos:
- repo: $HOOK_URL
  rev: v1.0.0
  hooks:
  - id: demo
- repo: $SECOND_URL
  rev: v1.0.0
  hooks:
  - id: other
EOF
cat > "$TMPDIR/new.yaml" <<EOF
repos:
- repo: $HOOK_URL
  rev: v2.0.0
  hooks:
  - id: demo
- repo: $SECOND_URL
  rev: v3.0.0
  hooks:
  - id: other
EOF
# Both entries share a URL, so `changed` pairs them by that URL; asserting on
# the file directly is what shows each line was rewritten independently.
run_cooldown 7
check "the held hook is reverted" "1" "$(grep -c 'rev: v1.0.0' "$TMPDIR/new.yaml")"
check "the aged hook keeps its update" "1" "$(grep -c 'rev: v3.0.0' "$TMPDIR/new.yaml")"

# Formatting around the rev is not the cooldown's to change. A revert must put
# the old value back inside the existing quoting and leave the comment alone.
cat > "$TMPDIR/old.yaml" <<EOF
repos:
- repo: $HOOK_URL
  rev: "v1.0.0"  # pinned deliberately
  hooks:
  - id: demo
EOF
cat > "$TMPDIR/new.yaml" <<EOF
repos:
- repo: $HOOK_URL
  rev: "v2.0.0"  # pinned deliberately
  hooks:
  - id: demo
EOF
run_cooldown 7
check "a revert preserves quoting and the trailing comment" \
  '  rev: "v1.0.0"  # pinned deliberately' \
  "$(grep 'rev:' "$TMPDIR/new.yaml")"

# A config the update did not touch is left byte for byte alone, so the cooldown
# never becomes a source of spurious diffs.
write_configs v1.0.0 v1.0.0
BEFORE=$(md5sum < "$TMPDIR/new.yaml" 2>/dev/null || md5 -q "$TMPDIR/new.yaml")
run_cooldown 7
AFTER=$(md5sum < "$TMPDIR/new.yaml" 2>/dev/null || md5 -q "$TMPDIR/new.yaml")
check "an unchanged config is not rewritten" "$BEFORE" "$AFTER"

# A malformed cooldown is a workflow configuration error. Treating it as zero
# would silently disable the protection the input exists to provide.
write_configs v1.0.0 v2.0.0
run_cooldown "not-a-number"
check "a non-numeric cooldown fails the run" "2" "$STATUS"
check "a non-numeric cooldown leaves the config alone" "v2.0.0" "$(current_rev)"

write_configs v1.0.0 v2.0.0
run_cooldown -1
check "a negative cooldown fails the run" "2" "$STATUS"

exit $FAIL
