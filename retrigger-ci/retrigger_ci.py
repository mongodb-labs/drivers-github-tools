"""Re-run a downstream repository's CI after a fork branch was force-pushed.

The downstream CI checks out the fork branch at a pinned ``ref:``, so a rebased
branch does not re-trigger it. This reads a ``ci_rerun`` mapping naming, per
fork branch, the downstream repositories and how to re-run each one.

The mapping shape matches the one the sync tooling already uses, so a mapping
can be copied across verbatim. Each downstream repository falls into one of
two cases, named by the value's type:

    {"mongodb/django-mongodb-backend": "main"}
        A merged branch. No pull request exists, so the downstream
        ``test-python*`` workflows are dispatched on it.

    {"mongodb/django-mongodb-backend": {"pr": 622, "evergreen": true}}
        An open pull request. Its checks gate the merge, so the workflow runs
        on its head commit re-run. ``evergreen`` adds a second call, since
        Evergreen pins the branch as Actions does and a rebase re-triggers
        neither.

A list may name several, mixing the two.

Best-effort: a stale PR number or an API error is reported and skipped rather
than failing the run, so one bad mapping entry cannot mask the branches that
synced correctly.
"""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys

# GitHub refuses to re-run a run older than this. Worth naming: the refusal
# otherwise looks like a permissions problem.
RETRY_WINDOW_HINT = "over a month ago"


class Skip(Exception):
    """A target could not be re-triggered. Reported, then execution continues."""


def warn(message: str) -> None:
    print(f"::warning::{message}")


def run_gh(args: list[str], dry_run: bool = False) -> str:
    """Run gh and return stdout. A dry run logs the call and returns nothing."""
    if dry_run:
        print(f"Would run: gh {' '.join(args)}")
        return ""
    result = subprocess.run(
        ["gh", *args], check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def gh_json(args: list[str]):
    """Run a read-only gh query and parse its JSON. Never subject to dry run."""
    out = run_gh(args)
    return json.loads(out) if out else []


def gh_error(exc: subprocess.CalledProcessError) -> str:
    """Pull the human-readable part out of gh's stderr.

    gh reports API failures as ``gh: <message> (HTTP <code>)``, sometimes after
    the raw JSON body, so callers can report why GitHub refused.
    """
    for line in reversed((exc.stderr or "").strip().splitlines()):
        line = line.strip()
        if line.startswith("gh: "):
            return line[4:].strip()
    lines = (exc.stderr or "").strip().splitlines()
    return lines[-1].strip() if lines else ""


def parse_ci_rerun(raw: str) -> dict[str, dict]:
    """Split the mapping into per-target lists of refs, PRs, and Evergreen PRs.

    Returns ``owner/name`` ->
    ``{"refs": [...], "prs": [...], "evergreen_prs": [...]}``, where
    ``evergreen_prs`` is the subset of ``prs`` that also want a retry comment.
    """
    try:
        mapping = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"::error::ci_rerun is not valid JSON: {exc}")
    if not isinstance(mapping, dict):
        raise SystemExit(f"::error::ci_rerun must be a JSON object, got {raw!r}")

    result: dict[str, dict] = {}
    for target, value in mapping.items():
        if "/" not in target or target.count("/") != 1 or not all(target.split("/")):
            raise SystemExit(
                f"::error::ci_rerun keys must be owner/name, got '{target}'"
            )
        refs: list[str] = []
        prs: list[int] = []
        evergreen_prs: list[int] = []
        for item in value if isinstance(value, list) else [value]:
            if isinstance(item, str):
                if item.isdigit():
                    raise SystemExit(
                        f"::error::ci_rerun: a pull request must be written "
                        f'{{"pr": {item}}}, not {item!r}, which reads as a git ref'
                    )
                refs.append(item)
            elif isinstance(item, dict):
                pr = item.get("pr")
                # A matrix value reaches us through YAML, so a number may
                # arrive quoted. bool subclasses int, so exclude it or `true`
                # parses as pull request #1.
                if isinstance(pr, str) and pr.isdigit():
                    pr = int(pr)
                if isinstance(pr, bool) or not isinstance(pr, int):
                    raise SystemExit(
                        f"::error::ci_rerun 'pr' must be a number, got {pr!r}"
                    )
                # The Actions runs always re-run; the flag adds Evergreen.
                prs.append(pr)
                if item.get("evergreen"):
                    evergreen_prs.append(pr)
            else:
                # Failing beats exiting clean, which would report success on
                # an untested downstream.
                raise SystemExit(
                    f"::error::ci_rerun: {item!r} is not a git ref or a "
                    '{"pr": N} object'
                )
        # A repeated entry would otherwise dispatch twice and post two
        # identical comments.
        result[target] = {
            "refs": list(dict.fromkeys(refs)),
            "prs": list(dict.fromkeys(prs)),
            "evergreen_prs": list(dict.fromkeys(evergreen_prs)),
        }
    return result


def pr_state(target: str, number: int) -> str | None:
    """Return OPEN/CLOSED/MERGED, or None if the lookup failed."""
    try:
        pr = gh_json(["pr", "view", str(number), "--repo", target, "--json", "state"])
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return None
    return pr.get("state") if isinstance(pr, dict) else None


def rerun_pr(target: str, number: int, dry_run: bool) -> None:
    """Re-queue every workflow run on an open PR's head commit.

    Every run, not just the test workflows: the lint and Evergreen checks gate
    the merge too, so all of them need re-validating.
    """
    print(f"Re-running CI on {target}#{number}")
    try:
        pr = gh_json(
            ["pr", "view", str(number), "--repo", target, "--json", "headRefOid,state"]
        )
        state = pr.get("state") if isinstance(pr, dict) else None
        if state and state != "OPEN":
            raise Skip(
                f"{target}#{number} is {state.lower()}; update the ci_rerun mapping"
            )
        head_sha = pr.get("headRefOid") if isinstance(pr, dict) else None
        if not head_sha:
            raise Skip(f"{target}#{number} returned no head commit")
        runs = gh_json(
            [
                "api",
                f"repos/{target}/actions/runs?head_sha={head_sha}&per_page=100",
                "--jq",
                "[.workflow_runs[].id]",
            ]
        )
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise Skip(f"could not resolve runs for {target}#{number}: {exc}")

    if not runs:
        raise Skip(f"{target}#{number} has no workflow runs on {head_sha}")

    requeued = 0
    reasons: list[str] = []
    for run_id in runs:
        try:
            run_gh(
                ["api", "-X", "POST", f"repos/{target}/actions/runs/{run_id}/rerun"],
                dry_run,
            )
            requeued += 1
        except subprocess.CalledProcessError as exc:
            reason = gh_error(exc)
            if reason and reason not in reasons:
                reasons.append(reason)

    if requeued or dry_run:
        print(f"  queued {requeued} workflow run(s)")
        return
    detail = f": {reasons[0]}" if reasons else ""
    if any(RETRY_WINDOW_HINT in r for r in reasons):
        detail += (
            f". These runs are past GitHub's retry window; push to the PR branch "
            f"to get fresh runs on #{number}"
        )
    raise Skip(f"no runs re-queued on {target}#{number}{detail}")


def retry_evergreen(target: str, number: int, dry_run: bool) -> None:
    """Comment ``evergreen retry`` so Evergreen starts a fresh patch.

    Evergreen pins the fork ref as Actions does, so a rebase does not re-run
    it. A closed or merged PR is skipped: Evergreen runs no patch for one.
    """
    print(f"Retrying Evergreen on {target}#{number}")
    state = pr_state(target, number)
    if state != "OPEN":
        # Unknown included: a failed lookup skips rather than guessing open,
        # since a comment on a closed pull request is noise nobody sees.
        detail = state.lower() if state else "of unknown state"
        raise Skip(f"{target}#{number} is {detail}; update the ci_rerun mapping")
    try:
        run_gh(
            ["pr", "comment", str(number), "--repo", target, "--body", "evergreen retry"],
            dry_run,
        )
    except subprocess.CalledProcessError as exc:
        raise Skip(f"could not comment on {target}#{number}: {gh_error(exc)}")
    print("  commented 'evergreen retry'")


def dispatch_workflows(target: str, ref: str, pattern: str, dry_run: bool) -> None:
    """Dispatch the downstream test workflows on a branch or tag.

    No PR is needed: workflow_dispatch runs each definition as it exists on
    ``ref``, which pins the fork branch that definition checks out.
    """
    print(f"Dispatching CI on {target}@{ref}")
    try:
        workflows = gh_json(
            [
                "api",
                f"repos/{target}/actions/workflows",
                "--jq",
                f"[.workflows[] | select(.path | "
                f'test("workflows/{re.escape(pattern)}")) | .path]',
            ]
        )
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise Skip(f"could not list workflows in {target}: {exc}")

    if not workflows:
        raise Skip(f"no {pattern}* workflows found in {target}")

    # Only a workflow declaring workflow_dispatch can run on a ref; the rest
    # would 422. Inspect each definition at `ref`.
    dispatchable = []
    for path in sorted(workflows):
        name = path.split("/")[-1]
        try:
            content = run_gh(["api", f"repos/{target}/contents/{path}?ref={ref}", "--jq", ".content"])
            body = base64.b64decode(content).decode("utf-8", "replace")
            # Avoid a YAML dependency: the trigger has to appear in the file.
            if "workflow_dispatch" in body:
                dispatchable.append(path)
            else:
                print(f"  {name}: skipped, no workflow_dispatch trigger")
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr or ""
            # The Actions registry still lists workflows deleted at this
            # ref. Dispatching one would 422.
            if "404" in stderr or "Not Found" in stderr:
                print(f"  {name}: skipped, not present on {ref}")
                continue
            # Any other error is transient, so attempt the dispatch rather
            # than skip work over a failed inspection.
            dispatchable.append(path)

    if not dispatchable:
        raise Skip(f"no dispatchable {pattern}* workflows in {target} at {ref}")

    for path in dispatchable:
        name = path.split("/")[-1]
        try:
            run_gh(["workflow", "run", name, "--repo", target, "--ref", ref], dry_run)
            print(f"  dispatched {name}")
        except subprocess.CalledProcessError as exc:
            warn(f"could not dispatch {name} on {target}@{ref}: {gh_error(exc)}")


def main() -> int:
    raw = os.environ["CI_RERUN"].strip()
    pattern = os.environ.get("WORKFLOW_PATTERN") or "test-python"
    dry_run = os.environ.get("DRY_RUN") == "true"

    if not raw:
        print("ci_rerun is empty, nothing to re-trigger.")
        return 0

    targets = parse_ci_rerun(raw)

    actions: list[tuple] = []
    for target, spec in targets.items():
        for ref in spec["refs"]:
            actions.append((dispatch_workflows, target, ref, pattern))
        for number in spec["prs"]:
            actions.append((rerun_pr, target, number))
        for number in spec["evergreen_prs"]:
            actions.append((retry_evergreen, target, number))

    if not actions:
        print("ci_rerun named no targets, nothing to re-trigger.")
        return 0

    # Best-effort: one stale entry must not stop the rest. Failures warn, so
    # the run stays green and still says what was skipped.
    for func, *args in actions:
        try:
            func(*args, dry_run)
        except Skip as exc:
            warn(str(exc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
