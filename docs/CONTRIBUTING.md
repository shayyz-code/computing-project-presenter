# Contributing

## The loop

**Issue → branch → small PR → squash merge.** In that order, including for your own work. An issue that exists before the code gives the PR something to close and the milestone something to track; one written afterwards is just a changelog entry.

```bash
gh issue create --title "feat(slidekit): render PDF pages" --label "type:feat,area:slidekit" --milestone "M1 Slides"
git checkout -b feat/12-render-pdf-pages
# ... work, committing as you go ...
gh pr create --title "feat(slidekit): render PDF pages" --body "...Closes #12"
```

### Branches

`<type>/<issue-number>-<slug>` — for example `feat/12-render-pdf-pages`, `fix/23-notes-off-by-one`, `docs/4-adr-set`.

Types: `feat`, `fix`, `docs`, `chore`.

### Commits and PR titles

[Conventional Commits](https://www.conventionalcommits.org/), with a scope:

```
feat(slidekit): render PDF pages at display scale
fix(mirrorkit): release the capture stream when the window closes
docs(adr): record the mirroring fallback
```

Scopes: `slidekit`, `mirrorkit`, `core`, `app`, `docs`, `ci`, `claude`, `repo`.

**The PR title matters more than the commit messages.** The repo squash-merges with `PR_TITLE` as the commit subject, so the PR title is what ends up in `main`'s history. A sloppy PR title produces a sloppy permanent record no matter how careful the individual commits were.

### Pull requests

Keep them small enough to review in one sitting. One issue, one PR.

Every PR body ends with `Closes #N`. Say what you verified and how — "ran `make test`, 11 passing" is useful; "should work" is not. If something is unverified, say that too; an honest gap is cheaper than a false claim.

Merging is squash-only, and branches delete themselves afterwards. Merge commits and rebase merges are disabled at the repo level, so there is no way to accidentally do it differently.

### Stacked pull requests

Sometimes a PR depends on one that has not merged yet, so its base is the branch below it rather than `main`. That shape is pleasant to review and dangerous to merge, because both of the ways it goes wrong are silent.

Branches delete themselves on merge, which pulls the base out from under whatever was stacked on top. GitHub then either retargets the child PR to `main` or closes it outright. During M0 it did both — same repository, minutes apart, no notification either time. **A closed PR cannot be retargeted, and a PR whose base branch is gone cannot be reopened.** Pushing the deleted branch back does not revive it. At that point the work has to move to a new PR.

Squash-merging is the other half. It creates a *new* commit, so the stacked branch's merge-base never advances and its diff grows to include everything underneath it.

So land a stack one PR at a time, bottom first, rebasing in between:

```bash
gh pr merge 10 --squash --delete-branch
git checkout main && git pull

# now the PR that was stacked on #10
git rebase --onto main <tip-of-the-old-base> ci/7-workflow
git push --force-with-lease origin ci/7-workflow
gh pr view 15 --json baseRefName        # must say "main" before you merge it
```

`--onto` with the old base tip is what drops the commits already absorbed into the squash. A plain `git rebase main` replays them and conflicts against files the squash commit already contains.

Do not batch this in a loop. A loop that redirects output hides the `git rebase` failure and carries on printing success — which is how M0's stack was lost while the terminal reported that every PR had landed.

## Before you push

```bash
make lint    # formatting, changes nothing
make test    # the package suite
make build   # the app still compiles
```

`make format` fixes formatting rather than just reporting it.

## Where decisions live

- **`docs/adr/`** — architecture decisions, with context and consequences. Changing one is a PR that edits the ADR, not a code change that quietly contradicts it.
- **`docs/specs/`** — acceptance criteria per capability. If a spec and the code disagree, one of them is a bug; decide which before writing more code.
- **`CLAUDE.md`** — orientation for agents and humans alike, including the traps worth knowing before touching PPTX parsing or capture.

## Spikes

Some questions are cheaper to answer with throwaway code than with reasoning. Both spikes so far — CoreMediaIO device capture and Keynote export — gated real design decisions, and both have landed.

A spike is labelled `type:spike`, time-boxed, and finishes by **updating its ADR with what was actually observed**. Code from a spike is not expected to survive. An answer that never reaches the ADR means the spike was wasted.

## Testing

Tests use [swift-testing](https://github.com/swiftlang/swift-testing) (`import Testing`), not XCTest.

Cover the awkward cases, not the happy path alone — empty decks, out-of-range jumps, denied permissions, a deck whose slides were reordered. Those are what break in front of an audience.

Tests needing TCC grants, a GUI session, or an external converter cannot run in CI. Tag them so they are excluded, and verify them by hand against real hardware. See CLAUDE.md for what CI does and does not cover.
