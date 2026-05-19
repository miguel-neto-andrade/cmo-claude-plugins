---
name: feature
description: "End-to-end feature finishing: detect the conventions skills the diff implies, run project-analyzer and code-reviewer in parallel against the branch, then open a PR. Use after completing feature work on a non-default branch."
---

# /feature — review-and-PR orchestrator

Run after feature work is committed (or staged) on a non-default branch. The command:

1. Verifies repo state (branch, base, has changes ahead).
2. Resolves which conventions skills apply to the diff (from changed files + repo signals).
3. Launches **`project-analyzer` and `code-reviewer` in parallel**, each passed the resolved skill list so they share one set of authoritative conventions and can't disagree about what the project's rules are.
4. Surfaces consolidated findings; blocks on Critical, asks before continuing past High.
5. Hands off to `/pr` to push and open the PR.

## Safety rules (non-negotiable)

1. **Invoking `/feature` is consent for committing any uncommitted work on this branch** — same rule as `/pr`. Don't ask; commit per `git-operations` after the review.
2. **Never** run from the default branch. Abort if `current == default`.
3. **Never** merge the PR. `/feature` opens it via `/pr`; a teammate reviews and merges.
4. **Both review agents must launch in parallel.** Send both Agent tool calls in a single message — not sequentially. The whole point of the command is to cut wall-clock time.
5. **Never fabricate findings or skill names.** If a skill is missing on disk, note it and continue with the rest.

## Procedure

Run each step in order. If any step fails, stop and report.

### 1. Repo state checks

```bash
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  for b in main master; do
    git show-ref --verify --quiet "refs/heads/$b" && DEFAULT_BRANCH=$b && break
  done
fi
CURRENT=$(git rev-parse --abbrev-ref HEAD)
```

Abort with a clear message if:
- `DEFAULT_BRANCH` is empty → "Could not determine default branch."
- `CURRENT == DEFAULT_BRANCH` → "You are on the default branch — switch to a feature branch first."
- `git rev-list --count "$DEFAULT_BRANCH"..HEAD` is `0` AND `git status --porcelain` is empty → "No changes ahead of $DEFAULT_BRANCH — nothing to review."

### 2. Collect the diff and resolve the skill list

Collect changed files across the full branch delta:

```bash
{
  git diff --name-only "$DEFAULT_BRANCH"...HEAD 2>/dev/null
  git diff --name-only 2>/dev/null
  git diff --name-only --staged 2>/dev/null
} | sort -u
```

Apply the same diff→skill mapping the `skill-reminder.sh` hook uses (it ran on this turn — its output is already in your context). Capture the resulting list as `SKILL_LIST`. Universal pairings:

- Any code change → add `coding-standards`.
- Any test path → add `testing-standards` (plus the stack's testing skill).
- Always include `git-operations` (the command will push + PR).

Ambiguous cases:
- `*.ts` / `*.js` with no `.vue` / `.tsx` / `.jsx` in the diff: disambiguate by `package.json` deps (`vue` → `vue-conventions`; `react` → `react-conventions`). If neither dep is present, omit the frontend convention.
- `CMakeLists.txt`: only treat as firmware when `platformio.ini` is present or the file mentions `STM32` / `ESP-IDF` / `Zephyr` / `nRF` / `FreeRTOS`.

If `SKILL_LIST` is empty after mapping (e.g., the diff only touches docs/config), set `REVIEW_SCOPE=docs` and **skip step 3** — go straight to step 5.

### 3. Launch the review pipeline — IN PARALLEL

Send **a single message containing two Agent tool calls** (one for each agent). They must run concurrently.

#### 3a. Common prompt prefix (used for both agents)

```
Conventions skills (authoritative for this review): <SKILL_LIST>

Load each one before reviewing. Treat their rules as the project's conventions —
do not flag a pattern as a smell when one of these skills prescribes it. When
generic best practice and a loaded skill disagree, the skill wins.

Diff scope: commits ahead of <DEFAULT_BRANCH> on branch <CURRENT>, plus any
staged/unstaged changes. Use `git diff "<DEFAULT_BRANCH>"...HEAD`, `git diff`,
and `git diff --staged` to see the full delta.
```

#### 3b. Agent call 1 — project-analyzer

`subagent_type: cmo-core:project-analyzer`. Pass the common prefix plus:

```
Scope: the directories touched by the branch diff. Run the full multi-phase
analysis (architecture / patterns / smells / errors / coupling / security)
but constrain findings to files changed in this branch — do not flag issues
in unchanged code.
```

#### 3c. Agent call 2 — code-reviewer

`subagent_type: cmo-core:code-reviewer`. Pass the common prefix plus:

```
Review the branch diff for security, code quality, architecture, and
performance issues. Use git diff against <DEFAULT_BRANCH> to see the full
delta. Apply the confidence filter (>80% sure it's a real issue) and the
severity output format documented in the agent definition.
```

Wait for both agents to return.

### 4. Consolidate and gate

Merge the two reports:

1. **Deduplicate** — if both agents flagged the same `file:line` for overlapping reasons, keep one (prefer the more specific recommendation; if equally specific, prefer the code-reviewer's framing since it's diff-scoped).
2. **Sort by severity** — Critical → High → Medium → Low.
3. **Present** a single combined summary using this shape:

```
## Review Summary (project-analyzer + code-reviewer)

| Severity | project-analyzer | code-reviewer | Consolidated |
|----------|-----------------:|--------------:|-------------:|
| Critical | <n>              | <n>           | <n>          |
| High     | <n>              | <n>           | <n>          |
| Medium   | <n>              | <n>           | <n>          |
| Low      | <n>              | <n>           | <n>          |

Verdict: <PASS | WARN | BLOCK>

<Then list the merged findings table — Severity / Finding / Location / Principle/Rule / Recommendation>
```

4. **Gate**:
   - **Any Critical** → BLOCK. Tell the user the PR is not being opened and list the Critical findings. Offer to apply fixes for trivial ones (typos, missing null checks, obvious refactors). Stop the command — do not proceed to step 5.
   - **Any High** → WARN. Ask the user: "X HIGH issue(s) detected. Fix before opening the PR, or proceed and surface them in the PR body?" Default to fix-first unless the user says proceed.
   - **Medium / Low only** → PASS. Surface in the report but proceed to step 5 automatically.

### 5. Open the PR

Follow the procedure documented in `commands/pr.md` from step 1 onward. Don't duplicate its logic here — read that file if needed and execute it. In particular:

- Commit any uncommitted work per `git-operations` (Conventional Commits, no `add -A`, no `--no-verify`, no `.claude/`, no AI attribution).
- Run the project-type classification (cloud-api / cloud-html / frontend / firmware / unknown) and gather the matching evidence.
- Push, create the PR, and capture the URL.

If `REVIEW_SCOPE=docs` (no code in the diff), the project-type evidence sections will mostly be empty — that's fine, `/pr` already skips empty sections.

### 6. Report

End with this shape:

```
Feature finished.
Branch:    <CURRENT>
Review:    project-analyzer (<X findings>) + code-reviewer (<Y findings>) — verdict: <PASS|WARN|BLOCK>
Skills:    <comma-separated SKILL_LIST>
PR:        <pr-url> (open — awaiting review)
Next:      teammate reviews and merges
```

If the review BLOCKED, omit the `PR:` line and replace `Next:` with: `Next: fix Critical findings, then re-run /feature`.

## Out of scope

- Implementing the feature itself — `/feature` runs **after** the work is done.
- Merging the PR (a human reviews and merges).
- Re-running on a branch that already has an open PR — `/pr`'s step 9 will fail, and that's intentional. Push fixes manually or close the existing PR first.
- Running the analyzer / reviewer sequentially — parallel is the point. If you find yourself sending them one after the other, stop and re-do step 3 with a single message that contains both tool calls.
