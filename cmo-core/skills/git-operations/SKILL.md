---
name: git-operations
description: Git and GitHub operations — commits, branches, PRs (creating, reviewing, or commenting), issues, and repository management. Use when running git or gh CLI commands, pushing, pulling, diffing, logging, or managing any repository task.
---

# Git & GitHub Operations

## Identity

- Act as the user. Never mention or indicate that Claude authored or co-authored any commit, PR, or message.
- **Never** add `Co-Authored-By` lines or any AI attribution to commit messages.

## Commits

- **Never** commit without explicit user consent.
- **CRITICAL: Never commit the `.claude/` directory.** Before the first commit of any session, verify `.claude/` is in `.git/info/exclude` — if not, add it. Never use `git add -f` on anything under `.claude/`. Never create commits that touch `.claude/` files, even for CLAUDE.md updates. If `.claude/` accidentally enters history, immediately rewrite history to remove it and force push.
- Before committing, check if the project contains a `README.md` or similar documentation (e.g., `CHANGELOG.md`, `docs/`) that should be updated to reflect the changes being committed. If updates are needed, make them before committing.
- **Semantic commits**: Every commit must be a single logical change. When multiple unrelated changes exist (e.g., a feature + a bug fix + a docs update), split them into separate commits. Stage files selectively with `git add <file>` — never bulk-add unrelated changes into one commit.
- **Conventional commits**: Use prefixes — `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`. Imperative mood, concise first line (<72 chars).

## Branching

- Use prefixes: `feature/`, `fix/`, `chore/`, `docs/`.
- Always branch from main/base branch.
- Delete branches after merge.

## Safety

- **Never** force push to main or shared branches.
- **Never** skip hooks (`--no-verify`).

## File Operations

- **Always use `git mv`** when moving or renaming files — never delete and recreate. This preserves git history and produces clean diffs (renames instead of delete+create).

## GitHub CLI

- Use `gh` CLI for all GitHub operations (issues, PRs, releases, API calls).
- Use appropriate labels and assignees.
- Follow project-specific branching strategies.
- Keep PRs focused and manageable in size.

## Pull Requests

PR descriptions must include:

1. **Summary** — Brief description of what was done and why.
2. **Code changes** — Concise summary of the files/areas changed and what each change does.

## PR Review

- Check CI status before approving.
- Leave actionable comments, not just "looks good".
- Attach comments to specific code lines whenever possible rather than leaving general PR-level comments.
