"""Read and rewrite the ``rev:`` fields of a ``.pre-commit-config.yaml``.

The file is handled as lines rather than parsed into a YAML object and dumped
back, which is also how ``pre-commit autoupdate`` itself rewrites revs. A
round trip through a YAML library reflows the document and drops every comment,
so a cooldown that reverted one rev would rewrite the whole file along with it.
A plain line scan is enough here because the two fields involved, ``repo:`` and
``rev:``, are always plain scalars.

Only the standard library is used, so the action runs on whatever interpreter
supplied ``pre-commit`` without needing an environment of its own. Requires
Python 3.10 or newer for the ``X | None`` annotations, which is well below what
any pre-commit release supports.
"""

import re
from typing import NamedTuple

# `- repo: <url>`, allowing a trailing comment. `local` and `meta` repos match
# too; they carry no rev, so they simply never pair with one below.
REPO_RE = re.compile(r"^\s*-\s+repo:\s*(?P<value>[^\s#]+)\s*(?:#.*)?$")

# `rev: <value>`, capturing the surrounding text so a rewrite can put the new
# value back without disturbing indentation, quoting, or a trailing comment.
REV_RE = re.compile(
    r"^(?P<prefix>\s*rev:\s*)"
    r"(?P<quote>['\"]?)(?P<value>[^\s'\"#]+)(?P=quote)"
    r"(?P<suffix>.*)$"
)


class Entry(NamedTuple):
    """A repo and the rev pinned for it, with the line the rev sits on."""

    repo: str
    rev: str
    line: int


def parse(lines: list[str]) -> list[Entry]:
    """Pair each ``repo:`` with the ``rev:`` that follows it.

    A repo with no rev, such as ``local`` or ``meta``, yields no entry. The
    first rev after a repo wins, so a stray later ``rev:`` cannot reattach
    itself to a repo that already has one.
    """
    entries: list[Entry] = []
    repo: str | None = None
    for index, line in enumerate(lines):
        repo_match = REPO_RE.match(line)
        if repo_match:
            repo = repo_match.group("value")
            continue
        if repo is None:
            continue
        rev_match = REV_RE.match(line)
        if rev_match:
            entries.append(Entry(repo, rev_match.group("value"), index))
            # Consumed: the next rev belongs to whichever repo comes next.
            repo = None
    return entries


def set_rev(lines: list[str], entry: Entry, rev: str) -> None:
    """Replace the rev on ``entry``'s line, preserving the rest of the line."""
    match = REV_RE.match(lines[entry.line])
    if match is None:  # pragma: no cover - the entry came from this same regex
        raise ValueError(f"line {entry.line + 1} is no longer a rev line")
    lines[entry.line] = (
        f"{match.group('prefix')}{match.group('quote')}{rev}"
        f"{match.group('quote')}{match.group('suffix')}"
    )


def read(path: str) -> list[str]:
    with open(path, encoding="utf-8") as handle:
        return handle.read().splitlines()


def write(path: str, lines: list[str]) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def short_name(repo: str) -> str:
    """Shorten a repo URL to ``owner/name`` for display.

    Falls back to the URL unchanged when it does not have two path segments to
    take, so an unusual remote is still identifiable in a summary.
    """
    trimmed = repo.rstrip("/")
    if trimmed.endswith(".git"):
        trimmed = trimmed[: -len(".git")]
    parts = [part for part in trimmed.split("/") if part]
    if len(parts) < 2:
        return repo
    return "/".join(parts[-2:])


def changed(old: list[Entry], new: list[Entry]) -> list[tuple[Entry, Entry]]:
    """Pair up entries whose rev moved between the two parses.

    Matching is by repo URL, so a repo added, removed, or reordered by the
    update is left out rather than being mistaken for a version change.
    """
    old_by_repo = {entry.repo: entry for entry in old}
    pairs = []
    for entry in new:
        previous = old_by_repo.get(entry.repo)
        if previous is not None and previous.rev != entry.rev:
            pairs.append((previous, entry))
    return pairs
