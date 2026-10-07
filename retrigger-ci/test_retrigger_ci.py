"""Tests for retrigger_ci.

Run with `python3 -m pytest retrigger-ci/test_retrigger_ci.py`.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))

import retrigger_ci as rc  # noqa: E402

BACKEND = "mongodb/django-mongodb-backend"

# Captured before a fixture replaces subprocess.run with the gh stub.
REAL_RUN = subprocess.run


# --- the ci_rerun mapping -------------------------------------------------
# The value's type selects the behaviour, and must parse as it does in the
# sync config, or a copied mapping re-triggers the wrong thing.


def parse(value):
    return rc.parse_ci_rerun(json.dumps({BACKEND: value}))[BACKEND]


def test_a_list_may_mix_the_forms():
    assert parse(["main", {"pr": 622}, {"pr": 602, "evergreen": True}]) == {
        "refs": ["main"],
        "prs": [622, 602],
        "evergreen_prs": [602],
    }


def test_a_key_that_is_not_owner_slash_name_is_rejected():
    """The key scopes the App token."""
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
        """Every call that changes downstream state."""
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
    """Dispatching one would 422."""
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
    """Lint and Evergreen gate the merge too, so all runs re-queue."""
    fake = gh(
        {
            "pr view": json.dumps({"state": "OPEN", "headRefOid": "abc123"}),
            "actions/runs?": "1\n2\n3",
        }
    )
    rc.rerun_pr(BACKEND, 607, dry_run=False)
    reruns = [c for c in fake.calls if "rerun" in " ".join(c)]
    assert len(reruns) == 3


def test_a_closed_pr_is_skipped(gh):
    """A stale mapping is a config bug to surface."""
    fake = gh({"pr view": json.dumps({"state": "MERGED", "headRefOid": "abc123"})})
    with pytest.raises(rc.Skip, match="merged"):
        rc.rerun_pr(BACKEND, 607, dry_run=False)
    assert not fake.mutating()


def test_evergreen_comments_the_retry(gh):
    """The body is the literal Evergreen looks for."""
    fake = gh({"pr view": json.dumps({"state": "OPEN"})})
    rc.retry_evergreen(BACKEND, 622, dry_run=False)
    assert ["gh", "pr", "comment", "622", "--repo", BACKEND, "--body",
            "evergreen retry"] in fake.calls


def test_a_wholly_failed_rerun_reports_the_reason_and_the_remedy(gh):
    """The refusal alone looks like a permissions problem."""
    gh(
        {
            "pr view": json.dumps({"state": "OPEN", "headRefOid": "abc123"}),
            "actions/runs?": "1",
        },
        fail_on={"rerun": "gh: Unable to retry this workflow run (HTTP 403)"},
    )
    with pytest.raises(rc.Skip, match="Unable to retry.*Push to the PR branch"):
        rc.rerun_pr(BACKEND, 607, dry_run=False)


# --- whole-run behaviour --------------------------------------------------


def test_one_bad_target_does_not_stop_the_others(gh, monkeypatch, capsys):
    """A stale entry must not mask a branch that synced."""
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
    """It would dispatch on a branch named '622'."""
    with pytest.raises(SystemExit, match="not '622'"):
        parse("622")


def test_a_value_that_is_neither_a_ref_nor_a_pr_is_rejected():
    """Exiting clean reports success on an untested downstream."""
    with pytest.raises(SystemExit):
        parse(622)
    with pytest.raises(SystemExit):
        parse(None)


def test_every_page_of_runs_is_requeued(gh):
    """Without --paginate, runs past per_page are left un-rerun."""
    fake = gh(
        {
            "pr view": json.dumps({"state": "OPEN", "headRefOid": "abc123"}),
            "actions/runs?": "\n".join(str(n) for n in range(150)),
        }
    )
    rc.rerun_pr(BACKEND, 607, dry_run=False)
    listed = next(c for c in fake.calls if "actions/runs?" in " ".join(c))
    assert "--paginate" in listed
    assert len([c for c in fake.calls if "rerun" in " ".join(c)]) == 150


def test_a_forbidden_definition_read_skips_rather_than_dispatching(gh):
    """403 is contents:read missing. Dispatching blind would 422."""
    fake = gh(
        {"actions/workflows": json.dumps([".github/workflows/test-python.yml"])},
        fail_on={"contents/": "gh: Resource not accessible by integration (HTTP 403)"},
    )
    with pytest.raises(rc.Skip, match="contents:read"):
        rc.dispatch_workflows(BACKEND, "main", "test-python", dry_run=False)
    assert not fake.mutating()


def test_a_partial_rerun_warns(gh, capsys):
    """A count alone would read as a clean re-run of the whole PR."""
    gh(
        {
            "pr view": json.dumps({"state": "OPEN", "headRefOid": "abc123"}),
            "actions/runs?": "1\n2\n3",
        },
        fail_on={"runs/2/rerun": "gh: Unable to retry this run (HTTP 403)"},
    )
    rc.rerun_pr(BACKEND, 607, dry_run=False)
    out = capsys.readouterr().out
    assert "queued 2 workflow run(s)" in out
    assert "::warning::1 of 3 runs" in out


def test_every_target_skipping_fails_the_run(gh, monkeypatch, capsys):
    """A wrong app id skips them all, and green reports a false success."""
    gh(fail_on={"": "gh: Bad credentials (HTTP 401)"})
    monkeypatch.setenv("CI_RERUN", json.dumps({BACKEND: ["main", {"pr": 622}]}))
    monkeypatch.setenv("DRY_RUN", "false")
    assert rc.main() == 1
    assert "::error::no targets re-triggered" in capsys.readouterr().out


def test_whitespace_only_stderr_does_not_crash():
    """An IndexError escapes Skip and aborts the run."""
    exc = subprocess.CalledProcessError(1, ["gh"], stderr="   ")
    assert rc.gh_error(exc) == ""


def test_evergreen_skips_when_the_state_lookup_fails(gh):
    """A failed lookup must not read as 'open'."""
    fake = gh(fail_on={"pr view": "gh: API rate limit exceeded (HTTP 403)"})
    with pytest.raises(rc.Skip, match="unknown state"):
        rc.retry_evergreen(BACKEND, 622, dry_run=False)
    assert not fake.mutating()


def jq_filter(gh, pattern, workflows):
    """Build the jq program, then run it under real jq.

    Asserting the string handed to a stubbed gh cannot catch a program jq
    refuses to compile, which is how the \\- escape bug shipped.
    """
    if shutil.which("jq") is None:
        pytest.skip("jq is not installed")
    fake = gh(
        {
            "actions/workflows": json.dumps([]),
            "contents/": b64("on:\n  workflow_dispatch:\n"),
        }
    )
    with pytest.raises(rc.Skip):
        rc.dispatch_workflows(BACKEND, "main", pattern, dry_run=False)
    listed = next(c for c in fake.calls if "actions/workflows" in " ".join(c))
    program = listed[listed.index("--jq") + 1]
    payload = json.dumps({"workflows": [{"path": p} for p in workflows]})
    # The fixture replaced subprocess.run, so use the one captured at import.
    result = REAL_RUN(
        ["jq", "-c", program], input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_the_jq_program_compiles(gh):
    """'\\-' in re.escape('test-python') is not a valid jq escape. Raw, jq
    refuses the program and nothing dispatches."""
    assert jq_filter(
        gh, "test-python", [".github/workflows/test-python.yml"]
    ) == [".github/workflows/test-python.yml"]


def test_a_dotted_pattern_is_matched_literally(gh):
    """Unescaped, '.' matches any character."""
    assert jq_filter(
        gh,
        "test-python.yml",
        [".github/workflows/test-python.yml", ".github/workflows/test-pythonXyml"],
    ) == [".github/workflows/test-python.yml"]


