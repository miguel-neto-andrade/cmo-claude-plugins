---
name: pr
description: "Push the current branch and open a pull request against the default branch. Never merges — a teammate reviews and merges manually."
---

# Create Pull Request

Push the current branch and open a PR against the default branch. The PR is **always** left open for a teammate to review and merge — this command never merges on its own.

## Safety rules (non-negotiable)

1. **Invoking `/pr` is consent for committing any uncommitted work on the current branch.** Don't ask — go straight to step 1. (Outside `/pr`, the normal "no commits without consent" rule still applies.)
2. **Never** create a PR from the default branch. Stop and report.
3. **Never** merge the PR (no `gh pr merge`, no `--admin`, no auto-merge flag). The whole point of this command is that a human reviews and merges.
4. **PR body must** include `## Summary` and `## Code changes` sections.
5. Follow the `git-operations` skill for everything else (Conventional Commits, no `add -A`, no `--no-verify`, no force-push, no `.claude/`, no AI attribution).

## Procedure

Run each step in order. If any step fails, stop and report.

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

### 5. Push the branch

```bash
git push -u origin HEAD   # or `git push` if upstream is already set
```

### 6. Draft the PR title and body

- **Title**: if the user passed an argument, use it verbatim. Otherwise use the subject line of the latest commit on this branch. Keep under 72 chars; preserve any conventional-commit prefix already present.
- **Body**: read `git log "$DEFAULT_BRANCH"..HEAD` and the diff to synthesize two sections:
  - **Summary** — what changed and why, in 1–3 bullets.
  - **Code changes** — files/areas touched and what each change does.

### 7. Create the PR

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary

<bullets>

## Code changes

- `<path>` — <what changed>
EOF
)"
```

Capture the PR URL from `gh`'s output.

### 8. Report

End with this shape:

```
PR:     <pr-url> (open — awaiting review)
Branch: <current-branch> pushed to origin
Next:   teammate reviews and merges
```

## Out of scope

- Merging the PR (use the GitHub UI after review)
- Amending or rebasing existing commits
- Editing or closing existing PRs
- Deleting the feature branch (the teammate's merge will do this, or `/clear-repo` afterwards)
