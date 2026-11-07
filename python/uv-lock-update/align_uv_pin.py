"""Align [tool.uv] required-version with the uv Dependabot's updater ships.

Rewrites an unsatisfied pin in place to ``>=<dependabot uv>,<next minor>``,
one line, so surrounding comments survive. Step outputs (GITHUB_OUTPUT,
when set): ``aligned``, ``compatible`` (true when Dependabot's uv may run
this workspace), and ``old_pin``/``new_pin`` on a rewrite. Handled
situations exit 0; errors exit 2.
"""

import os
import re
import sys
import tomllib

from packaging.specifiers import InvalidSpecifier, SpecifierSet
from packaging.version import InvalidVersion, Version

USAGE = 2

# required-version = ">=0.12.12,<0.13"  # comment
# Groups: key, quote, value, tail, line ending (kept for CRLF round-trips).
PIN_LINE = re.compile(
    r"^(\s*required-version\s*=\s*)(['\"])(.*?)\2([^\r\n]*)(\r?\n?)$"
)
SECTION = re.compile(r"^\s*\[([^\]]+)\]\s*$")


def upper_bound(version: Version) -> str:
    """Smallest version the rewritten pin must still reject: the next minor."""
    major, minor = version.release[0], version.release[1]
    return f"{major}.{minor + 1}"


def write_outputs(**outputs: str) -> None:
    """Append step outputs to GITHUB_OUTPUT, when the action provides it.

    Values are single-line by construction: a TOML line match, str(Version).
    """
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as f:
        for key, value in outputs.items():
            f.write(f"{key}={value}\n")


def rewrite(path: str, old_pin: str, new_pin: str) -> bool:
    """Replace the ``[tool.uv]`` line carrying ``old_pin`` with ``new_pin``.

    Returns False when no line matches; endings preserved byte for byte.
    """
    # newline="": no universal-newline translation reserializing CRLF files.
    with open(path, encoding="utf-8", newline="") as f:
        lines = f.readlines()
    section = None
    for index, line in enumerate(lines):
        header = SECTION.match(line)
        if header:
            # Accept quoted table names like ["tool.uv"] too.
            section = header.group(1).strip().strip("'\"")
            continue
        if section != "tool.uv":
            continue
        match = PIN_LINE.match(line)
        if match and match.group(3) == old_pin:
            lines[index] = (
                f'{match.group(1)}"{new_pin}"'
                f"{match.group(4)}{match.group(5)}"
            )
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.writelines(lines)
            return True
    return False


def main() -> None:
    if len(sys.argv) != 3:
        print(
            "Usage: align_uv_pin.py <pyproject.toml> <dependabot-uv-version>",
            file=sys.stderr,
        )
        sys.exit(USAGE)
    path, dependabot_version = sys.argv[1:3]
    try:
        target = Version(dependabot_version)
    except InvalidVersion:
        print(
            f"align_uv_pin.py: not a valid version: {dependabot_version!r}",
            file=sys.stderr,
        )
        sys.exit(USAGE)
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        # uv lock reports the missing file itself; not our error.
        print(
            f"::notice::no pyproject.toml at {path}; "
            "nothing to align.",
        )
        write_outputs(aligned="false", compatible="false")
        return
    except tomllib.TOMLDecodeError as exc:
        print(f"align_uv_pin.py: {path} is not valid TOML: {exc}", file=sys.stderr)
        sys.exit(USAGE)
    pin = data.get("tool", {}).get("uv", {}).get("required-version")
    if not isinstance(pin, str) or not pin.strip():
        print(
            "::notice::pyproject.toml has no [tool.uv] required-version pin; "
            "nothing to align."
        )
        write_outputs(aligned="false", compatible="false")
        return

    # A prerelease Dependabot ships still counts: it is the uv Dependabot runs.
    try:
        spec = SpecifierSet(pin)
    except InvalidSpecifier:
        print(
            f"align_uv_pin.py: required-version is not a valid specifier: {pin!r}",
            file=sys.stderr,
        )
        sys.exit(USAGE)
    if spec.contains(target, prereleases=True):
        print(f"required-version already accepts Dependabot's uv {target}")
        write_outputs(aligned="false", compatible="true")
        return
    if len(target.release) < 2:
        print(
            f"align_uv_pin.py: {target} has no minor component to bound; "
            "expected a version like 0.13.7",
            file=sys.stderr,
        )
        sys.exit(USAGE)
    new_pin = f">={target},<{upper_bound(target)}"
    if not rewrite(path, pin, new_pin):
        print(
            "::warning::pyproject.toml carries a required-version pin this "
            "script cannot rewrite in place (for example a dotted key); "
            "skipping required-version alignment. The lock update continues "
            "with the uv on PATH."
        )
        write_outputs(aligned="false", compatible="false")
        return
    print(f"Aligned required-version with Dependabot's uv: {pin} → {new_pin}")
    write_outputs(aligned="true", compatible="true", old_pin=pin, new_pin=new_pin)


if __name__ == "__main__":
    main()
