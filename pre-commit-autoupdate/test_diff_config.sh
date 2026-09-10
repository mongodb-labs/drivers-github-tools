#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/diff_config.py"
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

run_diff() {
  python3 "$SCRIPT" "$TMPDIR/old.yaml" "$TMPDIR/new.yaml"
}

# A rev that moved is reported as owner/name with both revs.
cat > "$TMPDIR/old.yaml" <<'EOF'
repos:
- repo: https://github.com/psf/black
  rev: 24.1.0
  hooks:
  - id: black
EOF
cat > "$TMPDIR/new.yaml" <<'EOF'
repos:
- repo: https://github.com/psf/black
  rev: 25.9.0
  hooks:
  - id: black
EOF
check "a changed rev is reported as owner/name with both revs" \
  '- psf/black: `24.1.0` → `25.9.0`' \
  "$(run_diff)"

# An unchanged rev produces nothing, so a run that only reordered the file does
# not open a pull request claiming version changes.
cp "$TMPDIR/old.yaml" "$TMPDIR/new.yaml"
check "an unchanged rev is not reported" "" "$(run_diff)"

# `local` and `meta` repos carry no rev. Pairing a repo with a rev further down
# the file would attach the next repo's rev to them and report a phantom change.
cat > "$TMPDIR/old.yaml" <<'EOF'
repos:
- repo: local
  hooks:
  - id: ruff
    entry: ruff check
- repo: https://github.com/psf/black
  rev: 24.1.0
  hooks:
  - id: black
EOF
cat > "$TMPDIR/new.yaml" <<'EOF'
repos:
- repo: local
  hooks:
  - id: ruff
    entry: ruff check
- repo: https://github.com/psf/black
  rev: 25.9.0
  hooks:
  - id: black
EOF
check "a revless local repo does not absorb the next repo's rev" \
  '- psf/black: `24.1.0` → `25.9.0`' \
  "$(run_diff)"

# Quoting and a trailing comment are both common in real configs, and neither
# is part of the rev value.
cat > "$TMPDIR/old.yaml" <<'EOF'
repos:
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: "v4.4.0"  # keep in sync with CI
  hooks:
  - id: check-yaml
EOF
cat > "$TMPDIR/new.yaml" <<'EOF'
repos:
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: "v6.0.0"  # keep in sync with CI
  hooks:
  - id: check-yaml
EOF
check "a quoted rev with a trailing comment reports only the rev" \
  '- pre-commit/pre-commit-hooks: `v4.4.0` → `v6.0.0`' \
  "$(run_diff)"

# Matching is by repo URL, so a repo present on only one side is not a change.
cat > "$TMPDIR/old.yaml" <<'EOF'
repos:
- repo: https://github.com/psf/black
  rev: 24.1.0
  hooks:
  - id: black
EOF
cat > "$TMPDIR/new.yaml" <<'EOF'
repos:
- repo: https://github.com/psf/black
  rev: 24.1.0
  hooks:
  - id: black
- repo: https://github.com/astral-sh/ruff-pre-commit
  rev: v0.6.0
  hooks:
  - id: ruff
EOF
check "an added repo is not reported as a version change" "" "$(run_diff)"

cat > "$TMPDIR/new.yaml" <<'EOF'
repos: []
EOF
check "a removed repo is not reported as a version change" "" "$(run_diff)"

# A URL with a .git suffix or a trailing slash names the same repo, and should
# read the same way in the summary.
cat > "$TMPDIR/old.yaml" <<'EOF'
repos:
- repo: https://github.com/psf/black.git
  rev: 24.1.0
  hooks:
  - id: black
EOF
cat > "$TMPDIR/new.yaml" <<'EOF'
repos:
- repo: https://github.com/psf/black.git
  rev: 25.9.0
  hooks:
  - id: black
EOF
check "a .git suffix is trimmed from the displayed name" \
  '- psf/black: `24.1.0` → `25.9.0`' \
  "$(run_diff)"

# Wrong argument counts are a caller bug, not an empty diff.
set +e
python3 "$SCRIPT" "$TMPDIR/old.yaml" > /dev/null 2>&1
STATUS=$?
set -e
check "a missing argument exits non-zero" "1" "$([ "$STATUS" -ne 0 ] && echo 1 || echo 0)"

exit $FAIL
