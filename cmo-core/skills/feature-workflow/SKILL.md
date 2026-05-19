---
name: feature-workflow
description: End-to-end feature delivery from spec to open PR — plan, implement, run project-analyzer + code-reviewer in parallel on the resulting diff, gate on Critical/High findings, then push and open the PR via /pr. Use ONLY when the user describes new functionality to build from scratch and wants it shipped. DO NOT trigger for tweaks, single-line fixes, refactors of existing code, isolated bug fixes, exploratory questions, debugging, or read-only tasks.
---

# Feature Workflow

End-to-end orchestration for shipping a new feature in one pass. Loads automatically when the user describes a new capability they want built-and-shipped. The skill defines a procedure — the model executes it.

## When this skill applies

USE when:
- The user describes a new capability to be built ("add an X endpoint", "build a Y page", "implement Z").
- The user expects the work to land as an open PR by the end of the conversation.
- The change is non-trivial (multiple files or a coherent unit of behaviour).

DO NOT USE when:
- The change is a tweak, typo, or one-line fix — just edit and commit.
- The user is debugging or investigating — there's no feature to ship yet.
- The user is asking how something works — read-only.
- The user explicitly says "don't open a PR" or "just edit the file."
- The work is a refactor of existing behaviour without new capability.

If you're unsure whether to engage, ask the user once. Don't run the procedure on a maybe.

## Source of truth

The conventions skills (`python-conventions`, `dotnet-conventions`, `vue-conventions`, `react-conventions`, `firmware-conventions`, etc.) are the **authoritative project conventions**. Both review agents in step 5 are passed the same list of conventions skills you loaded in step 3, so they can't disagree with each other or with your implementation. When generic best practice and a loaded conventions skill conflict, the skill wins.

## Isolation mode (parallel features)

When the user wants to build a feature without touching their main checkout — typically to ship multiple features in parallel from separate Claude Code sessions — they can request **isolation mode**. Treat any of these phrases in the feature request as the trigger:

- "in a worktree" / "use a worktree" / "worktree mode"
- "in isolation" / "isolated" / "isolated mode"
- "in parallel" (when context makes clear they mean parallel *feature* work, not parallel agent invocation)
- Flag-style: `--worktree`, `--isolated`, `--parallel`

When the trigger is present, perform these extra steps **before step 1 of the procedure**. (This section is project-instruction-directed worktree use, which is the supported path for `EnterWorktree`.)

### A. Pick the base

The worktree's branch is created from the parent session's current `HEAD`. Default behaviour: switch the parent session to the resolved default branch (`main`/`master`) and `git pull` first so the worktree starts from up-to-date upstream. If the parent session has uncommitted work, surface it and ask: stash, commit on the current branch, or proceed without switching base? Don't assume.

### B. Enter the worktree

Call `EnterWorktree` with a `name` derived from the feature scope using the `git-operations` branch convention (`feature/<slug>`, `fix/<slug>`, etc.). Slug = kebab-case of 2–4 keywords from the feature description. Example: feature description "add an endpoint for exporting widgets as CSV" → `name: "feature/widget-csv-export"`.

The harness creates `.claude/worktrees/feature/widget-csv-export` with a fresh branch of the same name and switches the session into it.

### C. Run the procedure inside the worktree

Steps 1–8 below execute **inside the worktree**. The branch `EnterWorktree` created is the branch step 7's PR opens from. The conventions skill list, the parallel review pair, and the gate logic all behave identically — only the working directory has moved.

### D. Don't auto-exit

**Never call `ExitWorktree` on your own.** Per the tool's contract, exit must be user-initiated. After step 7 opens the PR, the worktree stays in place so the user can:

- Keep working in it (follow-up commits, review feedback) — no action required.
- Switch back to the parent directory and leave the worktree intact → they ask to exit, you call `ExitWorktree(action: "keep")`.
- Discard it entirely (PR closed without merge, work abandoned) → they ask to remove, you call `ExitWorktree(action: "remove")`. If uncommitted work or unmerged commits exist, the tool refuses; surface what would be lost and confirm before re-invoking with `discard_changes: true`.

This is what makes parallel features work: each Claude Code session runs feature-workflow in its own worktree, the main checkout never moves, and the user controls cleanup per worktree.

## Procedure

Each step is a gate. Don't skip ahead.

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
- `CURRENT == DEFAULT_BRANCH` → "You are on the default branch — switch to a feature branch first, then re-describe the feature."

If the working tree has uncommitted changes that aren't part of this feature, surface them and ask whether to stash, commit, or discard before proceeding.

### 2. Plan

Read the user's feature description. If the scope spans more than a single file or a single coherent change:

- Spawn the `Plan` agent with the user's description as input.
- The Plan agent returns: files to touch (new vs modified), acceptance criteria, and open assumptions.
- **Surface the plan to the user before writing any code.** If the user redirects, update the plan and re-surface. Only proceed once the plan is acknowledged (explicit "yes/looks good", or unambiguous implicit consent like "go ahead").

For small-but-not-trivial features (single file, clear behaviour), state the plan inline in 2–3 sentences instead of spawning the Plan agent.

### 3. Resolve and load conventions skills

The diff doesn't exist yet, so derive the skill list from the **planned** file extensions and the repo's signals (`package.json` deps, `pyproject.toml`, `*.csproj`, `platformio.ini`, etc.) using the same mapping the `skill-reminder.sh` hook uses:

| Planned files | Skills to load |
|---|---|
| `*.py`, `pyproject.toml`, `requirements.txt` | `python-conventions` |
| `*.cs`, `*.csproj`, `*.sln`, `*.slnx` | `dotnet-conventions` (+ `dotnet-testing` if test paths) |
| `*.vue` | `vue-conventions` (+ `bootstrap-scss` if `*.scss` planned; + `ionic-capacitor` / `cmo-design-system` per `package.json`) |
| `*.tsx`, `*.jsx` | `react-conventions` (+ `bootstrap-scss` if `*.scss` planned; + `ionic-capacitor` / `cmo-design-system` per `package.json`) |
| `*.ts`, `*.js` (disambiguate by `package.json` deps) | `vue-conventions` or `react-conventions` |
| `*.scss`, `*.css` | `bootstrap-scss` |
| `*.c`, `*.h`, `*.cpp`, `*.hpp`, `*.ino`, `platformio.ini` | `firmware-conventions` |
| Any test path (`tests/`, `__tests__/`, `*.spec.*`, `*.test.*`, `*Tests.cs`, `test_*.py`) | `testing-standards` + the stack's testing skill |

Universal pairings:
- Any code work → also load `coding-standards`.
- Any git/PR step → load `git-operations` (you'll need it in step 7).

Load each skill via the `Skill` tool **before implementing**. Capture the resolved list as `SKILL_LIST` — you'll pass it to both review agents in step 5.

### 4. Implement

Write the code following the loaded conventions skills. Stick to the plan from step 2; if a deviation is necessary, surface it before continuing.

After each meaningful chunk:
- Run the project's build, type-check, or fast tests if one exists (e.g., `pnpm typecheck`, `dotnet build`, `ruff check`).
- Don't proceed to step 5 with a broken build or failing types — fix first.

For UI / frontend features, follow the standard rule: start the dev server and use the feature in a browser before declaring it done. Type-check ≠ feature-correctness.

### 5. Review (PARALLEL)

Launch `project-analyzer` AND `code-reviewer` in a **single message** containing two `Agent` tool calls. They must run concurrently — sequential invocation defeats the point of the orchestration.

**Common prompt prefix** (pass to both agents):

```
Conventions skills (authoritative for this review): <SKILL_LIST>

Load each one before reviewing. Treat their rules as the project's
conventions — do not flag a pattern as a smell when one of these
skills prescribes it. When generic best practice and a loaded skill
disagree, the skill wins.

Diff scope: commits ahead of <DEFAULT_BRANCH> on branch <CURRENT>,
plus any staged/unstaged changes. Use `git diff "<DEFAULT_BRANCH>"...HEAD`,
`git diff`, and `git diff --staged` to see the full delta.
```

**Agent call 1 — `cmo-core:project-analyzer`** — pass the common prefix plus:

> Scope: the directories touched by this branch's diff. Run the full multi-phase analysis (architecture / patterns / smells / errors / coupling / security) but constrain findings to files changed in this branch — do not flag issues in unchanged code.

**Agent call 2 — `cmo-core:code-reviewer`** — pass the common prefix plus:

> Review the branch diff for security, quality, architecture, and performance. Apply the >80% confidence filter and the severity output format documented in the agent definition.

Wait for both to return.

### 6. Consolidate and gate

Merge the two reports:

1. Deduplicate findings hitting the same `file:line`.
2. Sort by severity (Critical → High → Medium → Low).
3. Present a single combined summary:

```
## Review Summary (project-analyzer + code-reviewer)

| Severity | project-analyzer | code-reviewer | Consolidated |
|----------|-----------------:|--------------:|-------------:|
| Critical | <n>              | <n>           | <n>          |
| High     | <n>              | <n>           | <n>          |
| Medium   | <n>              | <n>           | <n>          |
| Low      | <n>              | <n>           | <n>          |

Verdict: <PASS | WARN | BLOCK>
```

Then the merged findings table (Severity / Finding / Location / Principle/Rule / Recommendation).

**Gate:**
- **Any Critical** → BLOCK. Don't open the PR. Fix the Criticals (apply trivial fixes directly; ask for direction on non-trivial ones), then **re-run step 5** on the new diff. Repeat until Critical = 0.
- **Any High** → WARN. Ask: "X HIGH issue(s) detected. Fix before opening the PR, or proceed and surface them in the PR body?" Default to fix-first unless the user says proceed.
- **Medium / Low only** → PASS. Surface in the report and proceed.

### 7. Push and open the PR

Follow the procedure in `commands/pr.md` from step 1 onward. Don't duplicate its logic here — read that file if needed and execute it. In particular:

- Commit any uncommitted work per `git-operations` (Conventional Commits, selective `git add`, no `--no-verify`, no `.claude/`, no AI attribution).
- Classify the project type (cloud-api / cloud-html / frontend / firmware / unknown) and gather the matching evidence.
- Push the branch, create the PR, capture the URL. Never merge.

### 8. Report

End with:

```
Feature shipped (PR open, awaiting review).
Branch:   <CURRENT>
Worktree: <path>  (only when isolation mode was used)
Skills:   <comma-separated SKILL_LIST>
Review:   project-analyzer (<X findings>) + code-reviewer (<Y findings>) — verdict: <PASS|WARN|BLOCK>
PR:       <pr-url>
Next:     teammate reviews and merges
```

If isolation mode was used, also remind the user: "The worktree stays open until you ask to exit it — say 'exit the worktree, keep it' or 'exit and remove the worktree' when you're done." Omit the Worktree line entirely when not in isolation mode.

If the gate BLOCKED at step 6 and you've already iterated, say so explicitly — list the rounds. If the user opted to "proceed with High issues", note the count in the PR body so the reviewer sees what was deferred.

## Out of scope

- Merging the PR — a human reviews and merges.
- Re-running the workflow on a branch that already has an open PR — surface this and ask whether to push fixes to the existing PR or close it first.
- Running analyzer / reviewer sequentially — if you find yourself sending the two `Agent` calls in two messages, stop and redo step 5 with one message containing both calls.
- Building features without a plan — for non-trivial scope, step 2 is mandatory, not optional.
