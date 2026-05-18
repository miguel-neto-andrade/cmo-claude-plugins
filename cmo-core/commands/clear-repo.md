---
name: clear-repo
description: "Switch to the default branch (main/master), then delete every local branch that has already been merged into it. Safe-by-default: never deletes unmerged work."
---

# Clear Repo

Clean up the local repository by switching back to the default branch and removing every local branch that has already been merged into it.

## When to use

- After finishing a feature and merging its PR — you want to drop the now-merged local branch.
- Periodically, to tidy up `git branch` output and reclaim mental overhead.

## Safety rules (non-negotiable)

1. **Never** force-delete a branch (`-D`). Always use `-d`, which only succeeds for fully merged branches. If `-d` refuses, leave the branch alone and report it.
2. **Never** delete the default branch (`main` or `master`), the current branch, or any branch listed as `protected` in repo config.
3. **Never** delete release-line branches. This includes:
   - Anything matching `release/*` (e.g. `release/2026.04`, `release/v3`)
   - Version-style branches matching `^v?\d+(\.(\d+|x))+$` (e.g. `1.x`, `1.0.x`, `2.1.3`, `v4.x.x`)
   These are long-lived integration / maintenance lines and must be preserved even when fully merged into the default branch.
4. **Never** touch remote branches. This command only operates on local refs.
5. **Never** run `git reset --hard`, `git clean -fd`, or any other destructive operation. Branch deletion only.
6. If the working tree has uncommitted changes, **stop** and report — do not switch branches.

## Procedure

Run each step in order. If any step fails, stop and report the failure.

### 1. Sanity-check the working tree

```bash
git status --porcelain
```

If output is non-empty, abort with: "Working tree is dirty — commit or stash before clearing." Do not proceed.

### 2. Detect the default branch

Try in this order, stopping at the first that succeeds:

```bash
# Preferred: the remote's HEAD ref
git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'

# Fallback: look for main, then master, locally
git show-ref --verify --quiet refs/heads/main && echo main \
  || git show-ref --verify --quiet refs/heads/master && echo master
```

Store the result as `DEFAULT_BRANCH`. If neither resolves, abort with: "Could not determine default branch."

### 3. Switch to the default branch

```bash
git checkout "$DEFAULT_BRANCH"
```

If `git fetch --prune` is also useful here (to update merge status from the remote), run it — but do not pull or rebase.

```bash
git fetch --prune
```

### 4. List merged branches

```bash
git branch --merged "$DEFAULT_BRANCH" --format='%(refname:short)'
```

From that list, exclude:
- `$DEFAULT_BRANCH` itself
- `main` and `master` (always — even if not the default)
- The current branch (should already be `$DEFAULT_BRANCH` at this point, but double-check)
- Any `release/*` branch (e.g. `release/2026.04`) — always skip, regardless of merge status
- Any version-style branch matching `^v?\d+(\.(\d+|x))+$` — e.g. `1.x`, `1.0.x`, `2.1.3`, `v4.x.x` — always skip
- Anything else that looks like a long-lived line (`develop`, `staging`, `production`) — skip with a note rather than delete

### 5. Delete each remaining branch

For every branch in the filtered list:

```bash
git branch -d "<branch>"
```

If `-d` refuses (branch not fully merged), **do not** retry with `-D`. Record it in the "skipped" list and move on.

### 6. Report

End with a short summary in this exact shape:

```
On branch: <default-branch>
Deleted (N): branch-a, branch-b, ...
Skipped (M): branch-x (reason), branch-y (reason)
```

If nothing was deleted, say: "Already clean — no merged branches to remove."

## Examples of branches to skip with a reason

- `release/*` (e.g. `release/2026.04`) — release line, always preserved
- Version-style branches like `1.x`, `1.0.x`, `2.1.3`, `v4.x.x` — release/maintenance lines, always preserved
- `develop`, `staging`, `production` — long-lived integration branches
- A branch whose name matches `wip/*` or contains `do-not-delete` — author flagged it
- Any branch `-d` refused — unmerged commits

## Out of scope

- Pushing, pulling, or rebasing
- Deleting remote branches (`git push origin --delete`)
- Pruning stash entries
- Garbage collection (`git gc`)
- Any operation that rewrites history
