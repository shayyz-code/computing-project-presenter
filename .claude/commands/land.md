---
description: Verify a PR's checks, squash-merge it, and confirm the issue closed
argument-hint: <PR number>
---

Land PR **#$ARGUMENTS**.

## Check before merging

1. `gh pr checks $ARGUMENTS` — CI must be green. Do not merge on a pending or failing run; if a check is failing for an unrelated reason, say so and let me decide.
2. `gh pr view $ARGUMENTS` — confirm the title is a valid conventional commit with a known scope. **It becomes the squash commit subject**, so a sloppy title is a permanent record. Fix it before merging, not after.
3. Confirm the body carries `Closes #N`. Without it the issue stays open and the milestone stops reflecting reality.
4. Check the base branch. If this PR is stacked on another, the one below it merges first.

## Merge

```bash
gh pr merge $ARGUMENTS --squash --delete-branch
```

Squash-only and auto-delete are enforced at the repo level, so the flags match what would happen anyway.

## After

Confirm the linked issue actually closed — `Closes #N` fails silently if the number is wrong or the PR targeted a non-default base.

Then update local `main`:

```bash
git checkout main && git pull
```

Report the merge commit and which issue closed. If the issue did not close, close it manually and say why it did not happen automatically.
