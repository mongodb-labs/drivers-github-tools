"""Diff two uv.lock files and print a markdown list of package version changes.

Requires Python 3.11 or newer for `tomllib`. The action pins this with
`uv run --python '>=3.11'`.
"""

import sys
import tomllib


def load_versions(path: str) -> dict[str, list[str]]:
    """Map each package name to its sorted list of locked versions.

    uv writes one ``[[package]]`` entry per resolution fork, so a package
    resolved differently across Python versions appears more than once. Keying
    on name alone would keep only the last entry parsed.

    Entries without a ``version`` key are skipped. uv writes such an entry for
    the root project itself (``source = { editable = "." }``), which has no
    locked version and does not belong in a version change summary.
    """
    with open(path, "rb") as f:
        data = tomllib.load(f)
    versions: dict[str, set[str]] = {}
    for pkg in data.get("package", []):
        if "version" not in pkg:
            continue
        versions.setdefault(pkg["name"], set()).add(pkg["version"])
    return {name: sorted(found) for name, found in versions.items()}


def format_versions(versions: list[str]) -> str:
    return ", ".join(f"`{version}`" for version in versions)


def diff_versions(
    old: dict[str, list[str]], new: dict[str, list[str]]
) -> list[str]:
    lines = []
    for name in sorted(set(old) | set(new)):
        old_versions = old.get(name)
        new_versions = new.get(name)
        if old_versions == new_versions:
            continue
        if old_versions is None:
            lines.append(f"- {name}: added {format_versions(new_versions)}")
        elif new_versions is None:
            lines.append(f"- {name}: removed {format_versions(old_versions)}")
        else:
            lines.append(
                f"- {name}: {format_versions(old_versions)}"
                f" → {format_versions(new_versions)}"
            )
    return lines


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: diff_lock.py <old.lock> <new.lock>", file=sys.stderr)
        sys.exit(2)
    old = load_versions(sys.argv[1])
    new = load_versions(sys.argv[2])
    for line in diff_versions(old, new):
        print(line)


if __name__ == "__main__":
    main()
