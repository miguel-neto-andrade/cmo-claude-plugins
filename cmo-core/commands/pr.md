---
name: pr
description: "Push the current branch and open a pull request against the default branch. Never merges — a teammate reviews and merges manually. Every PR follows a single canonical template; project-type detection decides only which optional sections get filled."
---

# Create Pull Request

Push the current branch and open a PR against the default branch. The PR is **always** left open for a teammate to review and merge — this command never merges on its own.

**Every PR — cloud-api, cloud-html, frontend, firmware, unknown — uses the single canonical template in [PR body template](#pr-body-template).** The template has fixed headings and a fixed section order. Optional sections appear only when they would have content and are dropped otherwise.

The project classification (step 5) decides what to *gather*, not what the body looks like:

- **Cloud APIs** populate the API-surface table.
- **Cloud HTML servers** and **frontends** populate Evidence via the Playwright MCP.
- **Every project type — firmware included** — populates Integration tests when integration tests were added or modified on this branch.
- **Unknown** types fall through to Summary + Code changes.

## Safety rules (non-negotiable)

1. **Invoking `/pr` is consent for committing any uncommitted work on the current branch.** Don't ask — go straight to step 1. (Outside `/pr`, the normal "no commits without consent" rule still applies.)
2. **Never** create a PR from the default branch. Stop and report.
3. **Never** merge the PR (no `gh pr merge`, no `--admin`, no auto-merge flag). The whole point of this command is that a human reviews and merges.
4. **Every PR uses the single template in [PR body template](#pr-body-template).** `## Summary` and `## Code changes` are required; the rest are optional and appear only when populated. No alternate templates per project type.
5. **Never fabricate evidence.** If a screenshot, endpoint signature, or test list can't be produced, write the gap into the body as a flag for the reviewer. Never invent data, fake screenshots, or silently skip.
6. **Never commit PR evidence.** Screenshots live outside the repo (temp dir + secret gist) — they must not appear in `git status` at any point, and `.pr-evidence/` must not exist in the working tree.
7. Follow the `git-operations` skill for everything else (Conventional Commits, no `add -A`, no `--no-verify`, no force-push, no `.claude/`, no AI attribution).

## Procedure

Run each step in order. If any step fails, stop and report. The temp evidence directory created in step 6c must always be deleted before exiting, whether the run succeeds or fails.

### 1. Commit any uncommitted work

If `git status --porcelain` is empty, skip to step 2.

Otherwise: read the diff, group changes into single-purpose commits, stage selectively (`git add <path>` or `-p`), commit per `git-operations`. **Never** amend or rewrite commits that existed before this run. On pre-commit hook failure, fix the cause and create a new commit — never `--no-verify`, never `--amend` past the failure.

### 2. Detect the default branch

Try in this order, stopping at the first that succeeds:

```bash
git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'
git show-ref --verify --quiet refs/heads/main && echo main \
  || git show-ref --verify --quiet refs/heads/master && echo master
```

Store as `DEFAULT_BRANCH`. If neither resolves, abort with: "Could not determine default branch."

### 3. Check the current branch

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
```

If `CURRENT` equals `DEFAULT_BRANCH`, abort with: "You are on the default branch — switch to a feature branch first."

### 4. Verify there are commits to PR

```bash
git rev-list --count "$DEFAULT_BRANCH"..HEAD
```

If the count is `0`, abort with: "No commits ahead of $DEFAULT_BRANCH — nothing to PR." Do not proceed.

### 5. Classify the project

Inspect the repo root and the changed files to assign one or more `PROJECT_TYPE` values:

| Type | Heuristic |
|---|---|
| `cloud-api` | Backend service exposing JSON/REST endpoints. Indicators: `*.csproj` with `Microsoft.AspNetCore.Mvc` + controllers but no `Views/` / `Pages/` / `*.razor`; FastAPI/Flask/Django REST Framework routes without templates; an OpenAPI/Swagger spec in repo. |
| `cloud-html` | Backend service rendering HTML. Indicators: ASP.NET Core MVC `Views/`, Razor Pages `Pages/`, Blazor `*.razor`, Django/Jinja `templates/`, Flask with `render_template`. |
| `frontend` | SPA / PWA. Indicators: `package.json` with `react`, `vue`, `next`, `nuxt`, `vite`, `ionic`, or `@capacitor/*`. No server-render entry point. |
| `firmware` | Embedded. Indicators: `platformio.ini`, `CMakeLists.txt` next to MCU code, STM32 / ESP-IDF / Zephyr / nRF layout. |
| `unknown` | None match cleanly. |

Monorepos: classify per top-level area touched by this branch's diff. A diff that hits both `api/` and `web/` is `cloud-api` + `frontend` — run both sub-procedures and include all relevant body sections.

Record the classification — it drives step 6 and the section-presence rules in step 8.

### 6. Gather section content

Run **6a** for every project type except `unknown`. Run the other sub-steps when the classification matches. For `unknown`, skip to step 7.

#### 6a. Integration tests (universal — all project types, firmware included)

Find tests added or modified in the integration tier:

```bash
git diff --name-status "$DEFAULT_BRANCH"..HEAD -- \
  '**/tests/integration/**' '**/IntegrationTests/**' '**/*.IntegrationTests/**' '**/integration/**'
```

For each new or modified test file, list the test methods (one bullet each) and mark them `[added]` or `[modified]`.

If a `cloud-api` change introduced endpoints but no integration test changed, the body must carry an explicit gap line — see the section-presence rules in step 8. For other project types (frontend, firmware), a missing integration-test entry is not automatically a gap; the section is simply omitted when empty.

#### 6b. API surface — `cloud-api` only

For each endpoint added or modified in this branch:

1. Find route handlers in `git diff "$DEFAULT_BRANCH"..HEAD`. Look for ASP.NET attribute routes (`[HttpGet]`, `[HttpPost]`, …), FastAPI decorators (`@router.get(...)`), Flask routes (`@app.route(...)`), Django URL patterns, or framework equivalents.
2. For each handler, capture from the surrounding code (do not invent): HTTP method, path, auth requirement, request shape (query/body), response shape and status codes.
3. Flag as **BREAKING** any endpoint that was renamed, removed, or had its contract changed (status, schema, auth, required params).

#### 6c. Playwright evidence — `cloud-html` and `frontend` only, hosted in a secret gist

You need the **Playwright MCP** tools loaded in this session. Check for `playwright_*` / `mcp__playwright__*` tools. If unavailable, skip capture and write `> Evidence pending — Playwright MCP not available in this session.` into the body under `## Evidence`. Do not fabricate.

**Privacy notice.** Screenshots upload to a **secret gist** — accessible to anyone with the URL, not auth-gated. If the change involves PHI, credentials, or other sensitive data on-screen, **skip 6c entirely** and write `> Evidence omitted — sensitive content not eligible for gist host.` into the body. Use your judgement, then proceed.

1. **Enumerate scenarios.** Read the diff and identify the distinct user-visible states this branch introduces or changes. Each scenario = one screenshot. Typical examples: empty form, populated form, validation-error state, success state, new tab, list with new column. Capture what proves the change works — don't shoot the whole app.
2. **Prepare a temp dir** outside the repo:

   ```bash
   EVIDENCE_DIR=$(mktemp -d -t cmo-pr-evidence-XXXX)
   ```

   Set up cleanup so this directory is removed even on failure (`trap "rm -rf \"$EVIDENCE_DIR\"" EXIT` in a shell wrapper, or equivalent — explicit `rm -rf` in step 11 also works).
3. **Start the dev server** using the project's standard command (`npm run dev`, `dotnet run`, `python manage.py runserver`, `pnpm dev`, etc.). Run it in the background. Note the URL.
4. **Capture each scenario** via Playwright MCP: navigate, drive the UI to the target state (fill inputs, click, wait for network idle), take a screenshot.
5. **Save** each capture to `$EVIDENCE_DIR/<scenario-slug>.png` (slug = kebab-case scenario name, e.g. `empty-form.png`, `validation-error.png`).
6. **Verify** no evidence file landed inside the working tree:

   ```bash
   test -z "$(git status --porcelain -- ':!:.gitignore')" || \
     { echo "evidence files leaked into the working tree — aborting"; exit 1; }
   ```

7. **Stop the dev server.**
8. **Upload to a secret gist** in one shot:

   ```bash
   GIST_URL=$(gh gist create -d "PR evidence: $CURRENT" "$EVIDENCE_DIR"/*.png)
   GIST_ID=${GIST_URL##*/}
   GH_LOGIN=$(gh api user -q .login)
   ```

   For each screenshot the raw URL is:

   ```
   https://gist.githubusercontent.com/<GH_LOGIN>/<GIST_ID>/raw/<filename>
   ```

   These render inline in the PR body. Keep `EVIDENCE_DIR` until step 11.

If capture or upload fails partway, record the missing scenarios in the body so the reviewer knows what's missing and why. Always continue to step 11 (cleanup) — never leave the temp dir behind.

### 7. Push the branch

```bash
git push -u origin HEAD   # or `git push` if upstream is already set
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### 8. Draft the PR title and body

- **Title**: if the user passed an argument, use it verbatim. Otherwise use the subject of the latest commit on this branch. Keep under 72 chars; preserve any conventional-commit prefix already present.
- **Body**: follow the single canonical template in [PR body template](#pr-body-template) below, regardless of project type. The template has a fixed heading order. **Drop any optional section that would be empty** — don't write "N/A".

Section order is always:

1. `## Summary` — required, always present.
2. `## Code changes` — required, always present.
3. `## API surface` — optional. Present when step 6b produced rows.
4. `## Integration tests` — optional. Present when step 6a produced bullets, **or** when 6b ran on `cloud-api` and produced endpoints with no integration coverage (in which case it carries only the gap-flag line).
5. `## Evidence` — optional. Present when step 6c ran (or produced one of the fallback lines).

Write the body to a temp file so `gh pr create --body-file` keeps multi-section bodies legible.

### 9. Create the PR

```bash
gh pr create --title "<title>" --body-file <body-file-path>
```

Capture the PR URL from `gh`'s output.

### 10. Report

End with this shape:

```
PR:       <pr-url> (open — awaiting review)
Branch:   <current-branch> pushed to origin
Project:  <PROJECT_TYPE(s)>
Evidence: <count> screenshots (gist: <gist-url>) / <count> endpoints / <count> integration tests / none
Next:     teammate reviews and merges
```

### 11. Clean up

```bash
rm -rf "$EVIDENCE_DIR"
```

Confirm `git status` is clean and no `.pr-evidence/` directory exists in the working tree.

## PR body template

The single canonical shape every PR follows. Headings, order, and section names are fixed. Required sections always appear; optional sections appear only when populated and are dropped otherwise — never write "N/A" or empty placeholders.

```markdown
## Summary

- <what changed, in 1–3 bullets>
- <why>

## Code changes

- `<path>` — <what changed>
- `<path>` — <what changed>

## API surface

| Method | Path | Auth | Request | Response | Notes |
|--------|------|------|---------|----------|-------|
| POST   | /api/widgets       | bearer | `{ name: string }`  | `201 { id, name }` | new |
| PATCH  | /api/widgets/{id}  | bearer | `{ name?: string }` | `200 { id, name }` | **BREAKING** — was PUT |

## Integration tests

- `tests/integration/WidgetsApiTests.cs`
  - `Post_CreatesWidget_ReturnsCreated` [added]
  - `Patch_UnknownId_Returns404` [added]
- `tests/integration/AuthFlowTests.cs`
  - `Bearer_Required_For_Widget_Routes` [modified]

## Evidence

Captured via Playwright MCP. Hosted in a secret gist — accessible by URL only: <gist-url>

### Empty form

![empty-form](https://gist.githubusercontent.com/<GH_LOGIN>/<GIST_ID>/raw/empty-form.png)

### Validation error

![validation-error](https://gist.githubusercontent.com/<GH_LOGIN>/<GIST_ID>/raw/validation-error.png)

### Success state

![success-state](https://gist.githubusercontent.com/<GH_LOGIN>/<GIST_ID>/raw/success-state.png)
```

### Section presence rules

| Section | Required? | When to include |
|---|---|---|
| `## Summary` | Yes | Always. |
| `## Code changes` | Yes | Always. |
| `## API surface` | No | `cloud-api` only, when 6b produced rows. |
| `## Integration tests` | No | Any project type — including firmware — when 6a produced bullets. Also include when `cloud-api` added endpoints but no integration test changed: in that case the section carries only the gap-flag line `> No integration tests added or modified — flag for reviewer.` |
| `## Evidence` | No | `cloud-html` or `frontend` only, when 6c ran (or produced a fallback line). |

### Evidence-section fallback lines

When step 6c can't produce all the expected screenshots, replace the relevant image line with one of these — never leave the section silently incomplete:

- A single scenario failed to capture: `> Capture failed: <one-line reason>`
- Playwright MCP wasn't available in the session: `> Evidence pending — Playwright MCP not available in this session.`
- Content was too sensitive for a secret gist: `> Evidence omitted — sensitive content not eligible for gist host.`

### Examples by project type

Same template, same heading order — only the set of populated sections differs:

- **`cloud-api`** — Summary, Code changes, API surface, Integration tests.
- **`cloud-html`** — Summary, Code changes, Integration tests (if any), Evidence.
- **`frontend`** — Summary, Code changes, Integration tests (if any), Evidence.
- **`firmware`** — Summary, Code changes, Integration tests (if any).
- **`unknown`** — Summary, Code changes.
- **Monorepo (e.g. `cloud-api` + `frontend`)** — every section that applies, in the fixed order above. No duplicates.

## Out of scope

- Merging the PR (use the GitHub UI after review)
- Amending or rebasing existing commits
- Editing or closing existing PRs (re-running `/pr` on a branch with an open PR will fail at step 9 — that's intentional)
- Deleting the feature branch (the teammate's merge will do this, or `/clear-repo` afterwards)
- Performance benchmarks or load-test results — out of `/pr`'s scope; use `testing-standards` if needed
- Cleaning up the evidence gist after merge (gists persist; let them — they're cheap, secret, and serve as historical evidence)
