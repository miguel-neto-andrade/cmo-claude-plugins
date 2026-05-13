---
name: pr
description: "Push the current branch and open a pull request against the default branch, then attempt to merge it only if existing branch-protection rules allow — never bypassing."
---

# Create Pull Request (and merge when allowed)

Push the current branch, open a PR against the default branch, and merge it — but only if existing branch-protection rules already permit a normal merge. Never bypass.

## Safety rules (non-negotiable)

1. **Invoking `/pr` is consent for committing any uncommitted work on the current branch.** Don't ask — go straight to step 1. (Outside `/pr`, the normal "no commits without consent" rule still applies.)
2. **Never** create a PR from the default branch. Stop and report.
3. **Never** pass `--admin`, retry with a different strategy, or otherwise relax checks. If a normal merge is blocked, leave the PR open and report.
4. **PR body must** include `## Summary` and `## Code changes` sections.
5. Follow the `git-operations` skill for everything else (Conventional Commits, no `add -A`, no `--no-verify`, no force-push, no `.claude/`, no AI attribution).

## Procedure

Run each step in order. If any step before the merge fails, stop and report. If the merge step itself is refused by branch protection, that is the expected fallback — leave the PR open and report it clearly.

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

Capture the PR URL from `gh`'s output and extract the PR number as `PR`.

### 8. Attempt a non-bypassing merge

```bash
gh pr merge "$PR" --squash --delete-branch || true
MERGED_STATE=$(gh pr view "$PR" --json state -q .state)
```

**Verify by PR state, not by `gh`'s exit code.** From a worktree where the default branch is checked out elsewhere, `gh pr merge` exits 1 *after* the remote merge already succeeded (only local cleanup failed). Trusting the exit code would falsely report "blocked by protection" on a PR that just landed.

If `MERGED_STATE` is `MERGED`, go to step 9. Otherwise go to step 10 — never retry with `--admin` or a different strategy.

### 9. If merged: finalize cleanup

`gh pr merge --delete-branch` covers this on a normal checkout, but may skip parts from a worktree. Finish each idempotently — don't report a failure for work `gh` already completed.

```bash
# Remote branch: delete only if it still exists.
if git ls-remote --exit-code --heads origin "$CURRENT" >/dev/null 2>&1; then
  git push origin --delete "$CURRENT"
fi

git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
git pull --ff-only

# Local branch: delete only if it still exists.
if git show-ref --verify --quiet "refs/heads/$CURRENT"; then
  git branch -d "$CURRENT"
fi
```

`-d` only — never `-D`. After this step both the remote and local feature branches MUST be gone. If `git branch -d` itself fails (e.g. the branch exists but is not fully merged locally), report the error verbatim — do not force-delete.

### 10. Report

If merged, end with this shape:

```
PR:           <pr-url> (merged)
Merge commit: <sha-on-default>
Local:        on <DEFAULT_BRANCH>, deleted <branch>
```

If left open because protection rules blocked the merge, end with:

```
PR:           <pr-url> (open)
Merge:        blocked by branch protection — <one-line reason from gh>
Next:         resolve the blocker (review / checks / etc.) and merge manually
```

## Out of scope

- Amending or rebasing existing commits
- Bypassing branch protection (`--admin`, dismissing reviews, disabling checks)
- Editing or closing existing PRs
- Merge strategies other than squash — run `gh pr merge` manually
