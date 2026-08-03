# Adopt GitHub Actions Self-Repository Syntax Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace this repo's 37 internal `mongodb-labs/drivers-github-tools/<path>@v3` self-references (plus 2 `./`-relative references in `update-action-tag.yml`) with GitHub Actions' new `$/<path>` self-repository syntax, eliminating the recurring manual-retagging maintenance burden — without changing behavior for external consumers.

**Architecture:** This is a mechanical YAML edit across 20 action/workflow files plus two doc updates. There is no application code and no unit-test suite here — correctness is verified via `pre-commit` (`check-github-actions` JSON-schema validation of `action.yml` files) and `zizmor` (GitHub Actions security static analysis, run both locally via `uvx` and in the repo's `.github/workflows/zizmor.yml` CI job). The rollout is staged: migrate one self-contained action first, push it, and confirm CI is green before migrating the rest, per the ticket's explicit acceptance criterion.

**Tech Stack:** GitHub Actions (composite actions + reusable workflow YAML), `pre-commit`, `zizmor` (via `uvx zizmor`).

**Ticket:** [DRIVERS-3596](https://jira.mongodb.org/browse/DRIVERS-3596)

## Global Constraints

- Every `$/<path>` reference must NOT include an `@{ref}` suffix — GitHub rejects `$/<path>@ref` as malformed. (Confirmed via `actions/runner#4457` and by testing: zizmor <1.29.0 errors with `malformed uses ref: missing @<ref>`.)
- `$/` requires GitHub Actions runner ≥ 2.336.0 (shipped 2026-07-20). This repo has no self-hosted runners (`grep -rn "runs-on:" .github/workflows/*.yml` — all `ubuntu-latest`), so GitHub-hosted runners satisfy this automatically; there is nothing to configure.
- The repo's zizmor CI job (`.github/workflows/zizmor.yml`) runs `zizmorcore/zizmor-action@6599ee8b7a49aef6a770f63d261d214911a7ce02 # v0.6.0` with its `version` input left at the action's default of `"latest"` — this means CI will always fetch a zizmor build that understands `$/` (support landed in zizmor v1.29.0, 2026-08-01; verified locally that v1.28.0 fatally errors on `$/` refs but v1.29.0 parses them cleanly with zero new findings). No CI config change is required for this, but the canary step (Task 1) re-confirms it against the real CI environment, not just local `uvx`.
- Keep `update-action-tag.yml` retagging `v3` for external consumers unchanged (AC4) — this migration only touches how actions reference each other *internally*; it does not change the public `owner/repo/path@v3` interface that driver repos consume.
- No behavior change for any external consumer of these actions.

---

## File Structure

No new files are created. Files modified:

- `tag-version/action.yml` — canary migration (Task 1)
- `bump-version/action.yml`, `create-branch/action.yml`, `full-report/action.yml` — root-level actions (Task 2)
- `golang/pre-publish/action.yml`, `golang/publish/action.yml` (Task 3)
- `node/release_template.yml`, `node/sign_node_package/action.yml` (Task 4)
- `python/pre-publish/action.yml`, `python/post-publish/action.yml`, `python-labs/pre-publish/action.yml`, `python-labs/post-publish/action.yml` (Task 5)
- `ruby/build/action.yml`, `ruby/cleanup/action.yml`, `ruby/publish/action.yml` (Task 6)
- `.github/workflows/update-action-tag.yml` (Task 7)
- `README.md`, `CONTRIBUTING.md` (Task 8)

Every task's substitution follows the same rule: a `uses:` line matching `mongodb-labs/drivers-github-tools/<PATH>@v3` becomes `uses: $/<PATH>` (same leading whitespace and any `- ` step-list prefix preserved, only the value changes).

---

### Task 1: Canary migration — `tag-version/action.yml`

**Files:**
- Modify: `tag-version/action.yml:36`

**Interfaces:** None — this is a leaf composite-action reference change with no signature implications for other tasks.

- [ ] **Step 1: Make the change**

```bash
sed -i.bak -E 's#uses: mongodb-labs/drivers-github-tools/([^@]+)@v3#uses: $/\1#' tag-version/action.yml
rm tag-version/action.yml.bak
```

Confirm the only change is line 36 becoming:
```yaml
      uses: $/git-sign
```

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-github-actions --files tag-version/action.yml`
Expected: `Passed`

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml tag-version/action.yml`
Expected: exits non-zero only due to pre-existing `template-injection`/`github-env` findings already present in this file before this change (verify by comparing against `uvx zizmor@1.29.0 --config .github/zizmor.yml .` run against the pre-migration `main` branch — the finding count and lines for `tag-version/action.yml` must be identical). There must be **no** finding referencing `$/git-sign`, and no parse/model error.

- [ ] **Step 4: Commit**

```bash
git add tag-version/action.yml
git commit -m "DRIVERS-3596 Migrate tag-version to \$/ self-repository syntax (canary)"
```

- [ ] **Step 5: Push and validate in real CI before continuing**

This step requires the user's explicit go-ahead to push (per repo safety rules — pushing branches and opening PRs needs confirmation each time).

Ask the user to confirm pushing the branch and opening a PR (base `main`, using the actual fork/branch from `git remote get-url origin` and `git branch --show-current`). Once pushed, wait for `.github/workflows/zizmor.yml` and `.github/workflows/test.yml` to complete on GitHub's real runners/zizmor-action.

**Do not proceed to Task 2 until both checks are green on the pushed commit.** This is the explicit "validate one migrated action in CI before rolling out repo-wide" acceptance criterion — it confirms the real GitHub-hosted runner and the real `zizmor-action@latest` behave as observed locally, not just the local `uvx` sandbox.

---

### Task 2: Root-level actions — `bump-version`, `create-branch`, `full-report`

**Files:**
- Modify: `bump-version/action.yml:39`
- Modify: `create-branch/action.yml:42`
- Modify: `full-report/action.yml:39,48,54,59`

**Interfaces:** None.

- [ ] **Step 1: Make the changes**

```bash
sed -i.bak -E 's#uses: mongodb-labs/drivers-github-tools/([^@]+)@v3#uses: $/\1#' \
  bump-version/action.yml create-branch/action.yml full-report/action.yml
rm bump-version/action.yml.bak create-branch/action.yml.bak full-report/action.yml.bak
```

Resulting lines must be exactly:
- `bump-version/action.yml:39`: `      uses: $/git-sign`
- `create-branch/action.yml:42`: `    - uses: $/bump-version`
- `full-report/action.yml:39`: `      uses: $/authorized-pub`
- `full-report/action.yml:48`: `      uses: $/sbom`
- `full-report/action.yml:54`: `      uses: $/code-scanning-export`
- `full-report/action.yml:59`: `      uses: $/compliance-report`

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-github-actions --files bump-version/action.yml create-branch/action.yml full-report/action.yml`
Expected: `Passed`

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml bump-version/action.yml create-branch/action.yml full-report/action.yml`
Expected: no new findings beyond what existed for these files pre-migration (no `$/`-related or parse-error findings).

- [ ] **Step 4: Commit**

```bash
git add bump-version/action.yml create-branch/action.yml full-report/action.yml
git commit -m "DRIVERS-3596 Migrate root-level actions to \$/ self-repository syntax"
```

---

### Task 3: Golang actions

**Files:**
- Modify: `golang/pre-publish/action.yml:20,27`
- Modify: `golang/publish/action.yml:27,46`

**Interfaces:** None.

- [ ] **Step 1: Make the changes**

```bash
sed -i.bak -E 's#uses: mongodb-labs/drivers-github-tools/([^@]+)@v3#uses: $/\1#' \
  golang/pre-publish/action.yml golang/publish/action.yml
rm golang/pre-publish/action.yml.bak golang/publish/action.yml.bak
```

Resulting lines:
- `golang/pre-publish/action.yml:20`: `    - uses: $/bump-version`
- `golang/pre-publish/action.yml:27`: `    - uses: $/tag-version`
- `golang/publish/action.yml:27`: `    - uses: $/full-report`
- `golang/publish/action.yml:46`: `      uses: $/upload-s3-assets`

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-github-actions --files golang/pre-publish/action.yml golang/publish/action.yml`
Expected: `Passed`

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml golang/pre-publish/action.yml golang/publish/action.yml`
Expected: no new findings vs. pre-migration baseline for these two files.

- [ ] **Step 4: Commit**

```bash
git add golang/pre-publish/action.yml golang/publish/action.yml
git commit -m "DRIVERS-3596 Migrate golang actions to \$/ self-repository syntax"
```

---

### Task 4: Node actions

**Files:**
- Modify: `node/release_template.yml:44,49,54,70,77,89,105`
- Modify: `node/sign_node_package/action.yml:45,50,73`

**Interfaces:** None.

- [ ] **Step 1: Make the changes**

```bash
sed -i.bak -E 's#uses: mongodb-labs/drivers-github-tools/([^@]+)@v3#uses: $/\1#' \
  node/release_template.yml node/sign_node_package/action.yml
rm node/release_template.yml.bak node/sign_node_package/action.yml.bak
```

Resulting lines:
- `node/release_template.yml:44`: `        uses: $/node/setup`
- `node/release_template.yml:49`: `        uses: $/node/get_version_info`
- `node/release_template.yml:54`: `        uses: $/node/sign_node_package`
- `node/release_template.yml:70`: `        uses: $/sbom`
- `node/release_template.yml:77`: `        uses: $/full-report`
- `node/release_template.yml:89`: `      - uses: $/upload-s3-assets`
- `node/release_template.yml:105`: `        uses: $/node/setup`
- `node/sign_node_package/action.yml:45`: `      uses: $/node/get_version_info`
- `node/sign_node_package/action.yml:50`: `      uses: $/setup`
- `node/sign_node_package/action.yml:73`: `      uses: $/gpg-sign`

Note: `node/release_template.yml:27` contains `uses: ./.github/workflows/build.yml` — a reusable-workflow relative reference, NOT part of this ticket's scope (the ticket only calls out the 37 `owner/repo@v3` self-references and the 2 `./`-relative refs in `update-action-tag.yml`). Leave this line untouched.

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-github-actions --files node/sign_node_package/action.yml`
Expected: `Passed` (note: `check-github-actions`'s file filter only matches `action.yml`/`action.yaml`, not `release_template.yml`, so it won't lint that file — this is expected and pre-existing, not something to fix here).

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml node/release_template.yml node/sign_node_package/action.yml`
Expected: no new findings vs. pre-migration baseline for these two files.

- [ ] **Step 4: Commit**

```bash
git add node/release_template.yml node/sign_node_package/action.yml
git commit -m "DRIVERS-3596 Migrate node actions to \$/ self-repository syntax"
```

---

### Task 5: Python and python-labs actions

**Files:**
- Modify: `python/pre-publish/action.yml:68,76`
- Modify: `python/post-publish/action.yml:73,81,92,127`
- Modify: `python-labs/pre-publish/action.yml:58`
- Modify: `python-labs/post-publish/action.yml:76`

**Interfaces:** None.

- [ ] **Step 1: Make the changes**

```bash
sed -i.bak -E 's#uses: mongodb-labs/drivers-github-tools/([^@]+)@v3#uses: $/\1#' \
  python/pre-publish/action.yml python/post-publish/action.yml \
  python-labs/pre-publish/action.yml python-labs/post-publish/action.yml
rm python/pre-publish/action.yml.bak python/post-publish/action.yml.bak \
   python-labs/pre-publish/action.yml.bak python-labs/post-publish/action.yml.bak
```

Resulting lines:
- `python/pre-publish/action.yml:68`: `      uses: $/bump-version`
- `python/pre-publish/action.yml:76`: `      uses: $/tag-version`
- `python/post-publish/action.yml:73`: `      uses: $/gpg-sign`
- `python/post-publish/action.yml:81`: `    - uses: $/full-report`
- `python/post-publish/action.yml:92`: `    - uses: $/upload-s3-assets`
- `python/post-publish/action.yml:127`: `      uses: $/bump-version`
- `python-labs/pre-publish/action.yml:58`: `      uses: $/tag-version`
- `python-labs/post-publish/action.yml:76`: `      uses: $/bump-version`

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-github-actions --files python/pre-publish/action.yml python/post-publish/action.yml python-labs/pre-publish/action.yml python-labs/post-publish/action.yml`
Expected: `Passed`

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml python/pre-publish/action.yml python/post-publish/action.yml python-labs/pre-publish/action.yml python-labs/post-publish/action.yml`
Expected: no new findings vs. pre-migration baseline for these four files.

- [ ] **Step 4: Commit**

```bash
git add python/pre-publish/action.yml python/post-publish/action.yml \
  python-labs/pre-publish/action.yml python-labs/post-publish/action.yml
git commit -m "DRIVERS-3596 Migrate python and python-labs actions to \$/ self-repository syntax"
```

---

### Task 6: Ruby actions

**Files:**
- Modify: `ruby/build/action.yml:37`
- Modify: `ruby/cleanup/action.yml:18`
- Modify: `ruby/publish/action.yml:60,83,97,102,125,179`

**Interfaces:** None.

- [ ] **Step 1: Make the changes**

```bash
sed -i.bak -E 's#uses: mongodb-labs/drivers-github-tools/([^@]+)@v3#uses: $/\1#' \
  ruby/build/action.yml ruby/cleanup/action.yml ruby/publish/action.yml
rm ruby/build/action.yml.bak ruby/cleanup/action.yml.bak ruby/publish/action.yml.bak
```

Resulting lines:
- `ruby/build/action.yml:37`: `      uses: $/secure-checkout`
- `ruby/cleanup/action.yml:18`: `      uses: $/secure-checkout`
- `ruby/publish/action.yml:60`: `      uses: $/secure-checkout`
- `ruby/publish/action.yml:83`: `      uses: $/setup`
- `ruby/publish/action.yml:97`: `      uses: $/gpg-sign`
- `ruby/publish/action.yml:102`: `      uses: $/full-report`
- `ruby/publish/action.yml:125`: `      uses: $/tag-version`
- `ruby/publish/action.yml:179`: `      uses: $/upload-s3-assets`

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-github-actions --files ruby/build/action.yml ruby/cleanup/action.yml ruby/publish/action.yml`
Expected: `Passed`

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml ruby/build/action.yml ruby/cleanup/action.yml ruby/publish/action.yml`
Expected: no new findings vs. pre-migration baseline for these three files.

- [ ] **Step 4: Commit**

```bash
git add ruby/build/action.yml ruby/cleanup/action.yml ruby/publish/action.yml
git commit -m "DRIVERS-3596 Migrate ruby actions to \$/ self-repository syntax"
```

---

### Task 7: `update-action-tag.yml` — replace `./`-relative references

**Files:**
- Modify: `.github/workflows/update-action-tag.yml:33,46`

**Interfaces:** None.

**Context:** The current file (lines 26–52) is:

```yaml
      - uses: actions/checkout@v7
        with:
          token: ${{ steps.app-token.outputs.token }}
          # Needed to push the tag in the final step
          persist-credentials: true

      - name: Setup
        uses: ./setup
        with:
          aws_role_arn: ${{ secrets.AWS_ROLE_ARN }}
          aws_region_name: ${{ vars.AWS_REGION_NAME }}
          aws_secret_id: ${{ secrets.AWS_SECRET_ID }}

      - name: Remove the existing tag
        run: |
          export VERSION=$(cat .github/workflows/version.txt)
          echo "VERSION=$VERSION" >> $GITHUB_ENV
          git push origin ":v${VERSION}" || true

      - name: Create a new signed tag
        uses: ./git-sign
        with:
          command: git tag -a "v${{ env.VERSION }}" -m "Update tag" -s --local-user=${{ env.GPG_KEY_ID }}

      - name: Push the tag
        run:
            git push origin --tags
```

The `actions/checkout` step **must stay** — it is independently required for two things unrelated to resolving `./setup`/`./git-sign`: (1) the `Remove the existing tag` step reads `.github/workflows/version.txt` from the local working copy, and (2) `persist-credentials: true` is what allows the final `git push origin --tags` and the tag-removal `git push` to authenticate. Per the ticket's AC ("drop the checkout step if no longer needed"), it IS still needed — do not remove it.

- [ ] **Step 1: Replace the two `./`-relative references**

Use the Edit tool (exact string match, not sed, since `./setup`/`./git-sign` are short strings that could otherwise collide):

Old:
```yaml
      - name: Setup
        uses: ./setup
```
New:
```yaml
      - name: Setup
        uses: $/setup
```

Old:
```yaml
      - name: Create a new signed tag
        uses: ./git-sign
```
New:
```yaml
      - name: Create a new signed tag
        uses: $/git-sign
```

- [ ] **Step 2: Validate schema locally**

Run: `pre-commit run check-yaml --files .github/workflows/update-action-tag.yml`
Expected: `Passed` (note: `check-github-actions`'s file filter only covers `action.yml`/`action.yaml`, not workflow files under `.github/workflows/`, so use `check-yaml` here instead).

- [ ] **Step 3: Validate security lint locally**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml .github/workflows/update-action-tag.yml`
Expected: no new findings vs. pre-migration baseline for this file, and specifically no finding about the retained `actions/checkout` step (it was already accepted pre-migration).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/update-action-tag.yml
git commit -m "DRIVERS-3596 Migrate update-action-tag.yml to \$/ self-repository syntax"
```

---

### Task 8: Update documentation

**Files:**
- Modify: `README.md:10-15`
- Modify: `CONTRIBUTING.md:31-32`

**Interfaces:** None.

**Context:** `README.md`'s "Working on Actions" section currently says:

```markdown
## Working on Actions

Many of the actions in this repo depend on one another.  There is no supported way to reference
another action using a relative path.  Therefore the recommended approach is to
set all of the relative actions to your branch name while working on a feature,
then reverting to the version tag before merging.
```

This is now inaccurate — GitHub Actions' `$/` self-repository syntax (runner ≥ 2.336.0) is exactly the "relative path" reference this text says isn't supported, and this repo's internal actions now use it.

- [ ] **Step 1: Update README.md**

Old:
```markdown
## Working on Actions

Many of the actions in this repo depend on one another.  There is no supported way to reference
another action using a relative path.  Therefore the recommended approach is to
set all of the relative actions to your branch name while working on a feature,
then reverting to the version tag before merging.
```
New:
```markdown
## Working on Actions

Many of the actions in this repo depend on one another. Internal action-to-action
references use GitHub Actions' `$/` self-repository syntax (e.g. `uses: $/setup`),
which always resolves to this repo at the exact commit currently running — no
version pin or checkout needed. This requires an Actions runner >= 2.336.0
(GitHub-hosted runners satisfy this automatically). Use `$/` for any new
internal reference instead of a pinned `mongodb-labs/drivers-github-tools/...@v3`
reference.
```

- [ ] **Step 2: Update CONTRIBUTING.md**

Old:
```markdown
To change the major version, update `.github/workflows/version.txt` and all references to `mongodb-labs/drivers-github-tools`
in the repo.
```
New:
```markdown
To change the major version, update `.github/workflows/version.txt`. Internal
action-to-action references use `$/` and do not need updating on a version bump.
Only update the example `mongodb-labs/drivers-github-tools/...@vX` references in
`README.md`, which document the tag external consumers should pin to.
```

- [ ] **Step 3: Verify rendering**

Run: `pre-commit run trailing-whitespace --files README.md CONTRIBUTING.md`
Expected: `Passed`

- [ ] **Step 4: Commit**

```bash
git add README.md CONTRIBUTING.md
git commit -m "DRIVERS-3596 Document \$/ self-repository syntax convention"
```

---

### Task 9: Full-repo verification and final push

**Files:** None modified — verification only.

**Interfaces:** None.

- [ ] **Step 1: Confirm zero remaining self-references outside README examples**

Run: `grep -rn "uses:.*mongodb-labs/drivers-github-tools" --include="*.yml" --include="*.yaml" --exclude-dir=.git --exclude-dir=.venv .`
Expected: zero matches (the only remaining `mongodb-labs/drivers-github-tools` mentions in the repo should be in `README.md`'s external-consumer example and `.github/zizmor.yml`'s `ref-pin` policy list, both intentionally unchanged).

- [ ] **Step 2: Confirm zero remaining in-scope `./`-relative references**

Run: `grep -n "uses: \./" .github/workflows/update-action-tag.yml`
Expected: zero matches.

- [ ] **Step 3: Run full pre-commit suite**

Run: `pre-commit run --all-files`
Expected: all hooks pass (or only pre-existing failures unrelated to this change — compare against a run on `main` before this branch's commits if any hook fails, to confirm it's not a regression).

- [ ] **Step 4: Run full zizmor scan and diff against pre-migration baseline**

Run: `uvx zizmor@1.29.0 --config .github/zizmor.yml . 2>&1 | tail -5`
Expected: the finding count/severity summary line matches the pre-migration baseline (89 findings: 4 informational, 10 low, 1 medium, 57 high — re-verify this baseline number on `main` at execution time, since it may drift from unrelated changes). There must be no new `unpinned-uses`, parse-error, or `$/`-related finding introduced by this migration.

- [ ] **Step 5: Push remaining commits and confirm CI green**

Ask the user for explicit confirmation before pushing (per repo safety rules). Push all commits from Tasks 2–8 to the same branch/PR opened in Task 1. Confirm `.github/workflows/zizmor.yml`, `.github/workflows/test.yml`, `.github/workflows/ci.yml`, and `.github/workflows/check-dist.yml` are all green on the final pushed state.

- [ ] **Step 6: Prepare PR description**

Per user's global CLAUDE.md instructions: keep the PR description high-level (what changed and why, not implementation mechanics), and there is no `.github` PR template in this repo to fill in (confirmed: `find .github -iname "*template*"` returns nothing). Reference DRIVERS-3596 and summarize: adopts GitHub's new `$/` self-repository syntax for the 37 internal action-to-action references (removing the recurring manual-retag maintenance cost), keeps `update-action-tag.yml` retagging `v3` for external consumers unchanged, and updates docs to reflect the new convention.
