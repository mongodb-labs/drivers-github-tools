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

Best-effort: a stale PR number or an API error warns and is skipped, so one
bad entry cannot mask the rest. Every entry skipping fails the run.
"""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys


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
    """Pull the message out of gh's ``gh: <message> (HTTP <code>)`` stderr."""
    for line in reversed((exc.stderr or "").strip().splitlines()):
        line = line.strip()
        if line.startswith("gh: "):
            return line[4:].strip()
    lines = (exc.stderr or "").strip().splitlines()
    return lines[-1].strip() if lines else ""


def parse_ci_rerun(raw: str) -> dict[str, dict]:
    """Split the mapping into per-target refs, PRs, and Evergreen PRs.

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
                # YAML may quote the number. bool subclasses int, so
                # exclude it or `true` parses as PR #1.
                if isinstance(pr, str) and pr.isdigit():
                    pr = int(pr)
                if isinstance(pr, bool) or not isinstance(pr, int):
                    raise SystemExit(
                        f"::error::ci_rerun 'pr' must be a number, got {pr!r}"
                    )
                # The runs always re-run; the flag adds Evergreen.
                prs.append(pr)
                if item.get("evergreen"):
                    evergreen_prs.append(pr)
            else:
                # Exiting clean would report success on an untested
                # downstream.
                raise SystemExit(
                    f"::error::ci_rerun: {item!r} is not a git ref or a "
                    '{"pr": N} object'
                )
        # A repeat would dispatch twice and comment twice.
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

    Every run, not just the test ones: lint and Evergreen gate the merge too.
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
        # --paginate, or runs past per_page are left un-rerun. With --jq it
        # prints one id per line across pages, not one array.
        out = run_gh(
            [
                "api",
                "--paginate",
                f"repos/{target}/actions/runs?head_sha={head_sha}&per_page=100",
                "--jq",
                ".workflow_runs[].id",
            ]
        )
        runs = [int(line) for line in out.split()]
    except (subprocess.CalledProcessError, ValueError) as exc:
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
        # A count alone would read as a clean re-run of the whole PR.
        if reasons:
            warn(
                f"{len(runs) - requeued} of {len(runs)} runs on {target}#{number} "
                f"did not re-queue: {'; '.join(reasons)}"
            )
        return
    # Report gh's reason, then the remedy. GitHub does not document the
    # refusal wording, and the remedy is the same whatever it is.
    detail = f": {reasons[0]}" if reasons else ""
    raise Skip(
        f"no runs re-queued on {target}#{number}{detail}. "
        f"Push to the PR branch to get fresh runs on #{number}"
    )


def retry_evergreen(target: str, number: int, dry_run: bool) -> None:
    """Comment ``evergreen retry`` so Evergreen starts a fresh patch.

    Evergreen pins the fork ref as Actions does, so a rebase does not re-run it.
    """
    print(f"Retrying Evergreen on {target}#{number}")
    state = pr_state(target, number)
    if state != "OPEN":
        # Unknown included: a comment on a closed PR is noise.
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

    workflow_dispatch runs each definition as it exists on ``ref``.
    """
    print(f"Dispatching CI on {target}@{ref}")
    # json.dumps quotes the regex for the jq string layer. Raw, the "\-" in
    # re.escape("test-python") is not a valid jq escape and nothing compiles.
    regex = json.dumps(f"workflows/{re.escape(pattern)}")
    try:
        workflows = gh_json(
            [
                "api",
                f"repos/{target}/actions/workflows",
                "--jq",
                f"[.workflows[] | select(.path | test({regex})) | .path]",
            ]
        )
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise Skip(f"could not list workflows in {target}: {exc}")

    if not workflows:
        raise Skip(f"no {pattern}* workflows found in {target}")

    # Only a workflow declaring workflow_dispatch can run on a ref.
    dispatchable = []
    for path in sorted(workflows):
        name = path.split("/")[-1]
        try:
            content = run_gh(["api", f"repos/{target}/contents/{path}?ref={ref}", "--jq", ".content"])
            body = base64.b64decode(content).decode("utf-8", "replace")
            # Avoid a YAML dependency: the trigger is in the file or not.
            if "workflow_dispatch" in body:
                dispatchable.append(path)
            else:
                print(f"  {name}: skipped, no workflow_dispatch trigger")
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr or ""
            # The registry still lists workflows deleted at this ref.
            if "404" in stderr or "Not Found" in stderr:
                print(f"  {name}: skipped, not present on {ref}")
                continue
            # A 403 is contents:read missing, so every inspection fails the
            # same way. Dispatching blind would just 422.
            if "403" in stderr or "Forbidden" in stderr:
                raise Skip(
                    f"could not read {path} in {target}: {gh_error(exc)}. The app "
                    f"token needs contents:read to inspect workflow definitions"
                )
            # Anything else is transient: dispatch rather than skip work.
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

    # Best-effort: one stale entry must not stop the rest.
    succeeded = 0
    for func, *args in actions:
        try:
            func(*args, dry_run)
            succeeded += 1
        except Skip as exc:
            warn(str(exc))

    # All of them skipping means a broken mapping or token, not a stale
    # entry. Green there reports success on an untriggered downstream.
    if not succeeded:
        print(f"::error::no targets re-triggered; all {len(actions)} were skipped")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
