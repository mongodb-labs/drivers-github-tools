#!/usr/bin/env bash
# Install the uv named by DEPENDABOT_UV under RUNNER_TEMP and write its path
# to the uv_bin step output (DRIVERS-3711). Any install failure warns and
# exits 0 with no uv_bin: tracking unavailable.
set -euo pipefail

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) target=x86_64-unknown-linux-gnu ;;
  Linux/aarch64) target=aarch64-unknown-linux-gnu ;;
  Darwin/arm64) target=aarch64-apple-darwin ;;
  Darwin/x86_64) target=x86_64-apple-darwin ;;
  *)
    echo "::warning::No prebuilt uv for $(uname -s)/$(uname -m); skipping required-version alignment. The lock update continues with the uv on PATH."
    exit 0
    ;;
esac

dir="${RUNNER_TEMP}/dependabot-uv-${DEPENDABOT_UV}"
mkdir -p "$dir"
# No checksum: one fetched from the same release shares its compromise;
# HTTPS to github.com/astral-sh is the anchor.
if ! curl -fsSL --connect-timeout 10 --max-time 120 -o "$dir/uv.tar.gz" \
  "https://github.com/astral-sh/uv/releases/download/${DEPENDABOT_UV}/uv-${target}.tar.gz" \
  || ! tar -xzf "$dir/uv.tar.gz" -C "$dir" --strip-components=1; then
  echo "::warning::Could not install Dependabot's uv ${DEPENDABOT_UV}; skipping required-version alignment. The lock update continues with the uv on PATH."
  exit 0
fi

if ! "$dir/uv" --version; then
  echo "::warning::Dependabot's uv ${DEPENDABOT_UV} did not run after extraction; skipping required-version alignment. The lock update continues with the uv on PATH."
  exit 0
fi
echo "uv_bin=$dir/uv" >> "$GITHUB_OUTPUT"
