"""Diff two .pre-commit-config.yaml files and print the rev changes as markdown.

Usage: diff_config.py <old-config> <new-config>

Run after the cooldown has been applied, so the summary describes the revs the
pull request actually carries rather than the ones autoupdate first proposed.
"""

import sys

import pre_commit_config as config


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: diff_config.py <old-config> <new-config>", file=sys.stderr)
        sys.exit(2)
    old = config.parse(config.read(sys.argv[1]))
    new = config.parse(config.read(sys.argv[2]))
    for previous, current in config.changed(old, new):
        name = config.short_name(current.repo)
        print(f"- {name}: `{previous.rev}` → `{current.rev}`")


if __name__ == "__main__":
    main()
