"""Tests for retrigger_ci.

Run with `python3 -m pytest retrigger-ci/test_retrigger_ci.py`.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))

import retrigger_ci as rc  # noqa: E402

BACKEND = "mongodb/django-mongodb-backend"


# --- the ci_rerun mapping -------------------------------------------------
# The value's type selects the behaviour. A mapping must parse the same here
# as in the sync config, or copying one across re-triggers the wrong thing.


def parse(value):
    return rc.parse_ci_rerun(json.dumps({BACKEND: value}))[BACKEND]


def test_a_list_may_mix_the_forms():
    assert parse(["main", {"pr": 622}, {"pr": 602, "evergreen": True}]) == {
        "refs": ["main"],
        "prs": [622, 602],
        "evergreen_prs": [602],
    }


def test_a_quoted_pr_number_still_parses():
    """A matrix value passes through YAML, so a number may arrive quoted."""
    assert parse({"pr": "622", "evergreen": True})["evergreen_prs"] == [622]


def test_a_key_that_is_not_owner_slash_name_is_rejected():
    """The key scopes the App token, so a malformed one must not reach gh."""
    with pytest.raises(SystemExit):
        rc.parse_ci_rerun(json.dumps({"django-mongodb-backend": "main"}))


# --- the two cases: a merged branch, and an open pull request -------------


class FakeGh:
    """Records gh calls and answers reads from canned responses."""

    def __init__(self, responses=None, fail_on=None):
        self.calls: list[list[str]] = []
        self.responses = responses or {}
        self.fail_on = fail_on or {}

    def __call__(self, args, check=True, capture_output=True, text=True):
        self.calls.append(args)
        key = " ".join(args[1:])
        for pattern, stderr in self.fail_on.items():
            if pattern in key:
                raise subprocess.CalledProcessError(1, args, stderr=stderr)
        for pattern, payload in self.responses.items():
            if pattern in key:
                return subprocess.CompletedProcess(args, 0, stdout=payload, stderr="")
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

    def mutating(self):
        """Every call that changes state downstream."""
        return [
            c
            for c in self.calls
            if c[1] in ("workflow", "pr") and c[2] in ("run", "comment")
            or ("-X" in c and "POST" in c)
        ]


@pytest.fixture
def gh(monkeypatch):
    def install(responses=None, fail_on=None):
        fake = FakeGh(responses, fail_on)
        monkeypatch.setattr(subprocess, "run", fake)
        return fake

    return install


WORKFLOWS = json.dumps(
    [
        ".github/workflows/test-python.yml",
        ".github/workflows/test-python-atlas.yml",
    ]
)
DISPATCHABLE = json.dumps({"content": ""})


def b64(text):
    import base64

    return base64.b64encode(text.encode()).decode()


def test_a_ref_dispatches_each_matching_workflow(gh):
    fake = gh(
        {
            "actions/workflows": WORKFLOWS,
            "contents/": b64("on:\n  workflow_dispatch:\n"),
        }
    )
    rc.dispatch_workflows(BACKEND, "6.0.x", "test-python", dry_run=False)
    dispatched = [c for c in fake.calls if c[1] == "workflow"]
    assert [c[3] for c in dispatched] == ["test-python-atlas.yml", "test-python.yml"]
    assert all(c[-1] == "6.0.x" for c in dispatched)


def test_a_workflow_without_a_dispatch_trigger_is_skipped(gh):
    """Dispatching one would 422, so each definition is inspected."""
    fake = gh(
        {
            "actions/workflows": json.dumps([".github/workflows/test-python.yml"]),
            "contents/": b64("on:\n  pull_request:\n"),
        }
    )
    with pytest.raises(rc.Skip):
        rc.dispatch_workflows(BACKEND, "main", "test-python", dry_run=False)
    assert not fake.mutating()


def test_a_pr_reruns_every_run_on_its_head_commit(gh):
    """Lint and Evergreen checks gate the merge too, so all runs re-queue."""
    fake = gh(
        {
            "pr view": json.dumps({"state": "OPEN", "headRefOid": "abc123"}),
            "actions/runs?": json.dumps([1, 2, 3]),
        }
    )
    rc.rerun_pr(BACKEND, 607, dry_run=False)
    reruns = [c for c in fake.calls if "rerun" in " ".join(c)]
    assert len(reruns) == 3


def test_a_closed_pr_is_skipped(gh):
    """A stale mapping is a config bug to surface, not act on."""
    fake = gh({"pr view": json.dumps({"state": "MERGED", "headRefOid": "abc123"})})
    with pytest.raises(rc.Skip, match="merged"):
        rc.rerun_pr(BACKEND, 607, dry_run=False)
    assert not fake.mutating()


def test_evergreen_comments_the_retry(gh):
    """The comment body is the literal Evergreen looks for."""
    fake = gh({"pr view": json.dumps({"state": "OPEN"})})
    rc.retry_evergreen(BACKEND, 622, dry_run=False)
    assert ["gh", "pr", "comment", "622", "--repo", BACKEND, "--body",
            "evergreen retry"] in fake.calls


def test_evergreen_skips_a_closed_pr(gh):
    fake = gh({"pr view": json.dumps({"state": "CLOSED"})})
    with pytest.raises(rc.Skip, match="closed"):
        rc.retry_evergreen(BACKEND, 607, dry_run=False)
    assert not fake.mutating()


def test_runs_past_the_retry_window_say_so(gh):
    """The refusal otherwise looks like a permissions problem."""
    fake = gh(
        {
            "pr view": json.dumps({"state": "OPEN", "headRefOid": "abc123"}),
            "actions/runs?": json.dumps([1]),
        },
        fail_on={"rerun": "gh: This run is over a month ago (HTTP 403)"},
    )
    with pytest.raises(rc.Skip, match="past GitHub's retry window"):
        rc.rerun_pr(BACKEND, 607, dry_run=False)


# --- whole-run behaviour --------------------------------------------------


def test_one_bad_target_does_not_stop_the_others(gh, monkeypatch, capsys):
    """Best-effort: a stale entry must not mask a branch that synced."""
    fake = gh(
        {
            "pr view": json.dumps({"state": "MERGED"}),
            "actions/workflows": json.dumps([".github/workflows/test-python.yml"]),
            "contents/": b64("on:\n  workflow_dispatch:\n"),
        }
    )
    monkeypatch.setenv("CI_RERUN", json.dumps({BACKEND: ["main", {"pr": 622}]}))
    monkeypatch.setenv("DRY_RUN", "false")
    assert rc.main() == 0
    out = capsys.readouterr().out
    assert "::warning::" in out
    assert any(c[1] == "workflow" and c[2] == "run" for c in fake.calls)


def test_an_empty_ci_rerun_does_nothing(gh, monkeypatch):
    fake = gh()
    monkeypatch.setenv("CI_RERUN", "")
    assert rc.main() == 0
    assert not fake.calls


def test_a_dry_run_makes_no_mutating_call(gh, monkeypatch, capsys):
    fake = gh(
        {
            "actions/workflows": json.dumps([".github/workflows/test-python.yml"]),
            "contents/": b64("on:\n  workflow_dispatch:\n"),
        }
    )
    monkeypatch.setenv("CI_RERUN", json.dumps({BACKEND: "main"}))
    monkeypatch.setenv("DRY_RUN", "true")
    assert rc.main() == 0
    assert not fake.mutating()
    assert "Would run: gh workflow run" in capsys.readouterr().out


# --- regressions ----------------------------------------------------------


def test_a_bare_number_is_rejected_not_read_as_a_ref():
    """It would otherwise dispatch on a branch named '622'."""
    with pytest.raises(SystemExit, match="not '622'"):
        parse("622")


def test_a_value_that_is_neither_a_ref_nor_a_pr_is_rejected():
    """Exiting clean would report success on an untested downstream."""
    with pytest.raises(SystemExit):
        parse(622)
    with pytest.raises(SystemExit):
        parse(None)


def test_duplicates_act_once():
    """Two dispatches race, and two Evergreen comments are noise."""
    assert parse(["main", "main"])["refs"] == ["main"]
    ever = parse([{"pr": 622, "evergreen": True}, {"pr": 622, "evergreen": True}])
    assert ever["prs"] == [622]
    assert ever["evergreen_prs"] == [622]


def test_whitespace_only_stderr_does_not_crash():
    """An IndexError escapes Skip and aborts the whole run."""
    exc = subprocess.CalledProcessError(1, ["gh"], stderr="   ")
    assert rc.gh_error(exc) == ""


def test_evergreen_skips_when_the_state_lookup_fails(gh):
    """A failed lookup must not read as 'open' and land a stray comment."""
    fake = gh(fail_on={"pr view": "gh: API rate limit exceeded (HTTP 403)"})
    with pytest.raises(rc.Skip, match="unknown state"):
        rc.retry_evergreen(BACKEND, 622, dry_run=False)
    assert not fake.mutating()


def test_a_pattern_with_a_dot_is_matched_literally(gh):
    """Unescaped, '.' matches any character and widens the scope."""
    fake = gh(
        {
            "actions/workflows": json.dumps([".github/workflows/test-python.yml"]),
            "contents/": b64("on:\n  workflow_dispatch:\n"),
        }
    )
    rc.dispatch_workflows(BACKEND, "main", "test-python.yml", dry_run=False)
    listed = [c for c in fake.calls if "actions/workflows" in " ".join(c)][0]
    assert "test\\-python\\.yml" in " ".join(listed) or "test\\-python\\.yml" in str(listed)
