---
description: Implement an issue on a branch and open a small PR
argument-hint: <issue number>
---

Implement issue **#$ARGUMENTS** and open a PR.

## Before writing code

Read the issue, its spec in `docs/specs/`, and any ADR it touches. If the issue has no acceptance criteria, stop and get them — implementing against a vague issue produces a PR nobody can review.

If the issue depends on an unresolved spike, stop and say so. Do not build on a provisional assumption.

## Branch

`<type>/$ARGUMENTS-<slug>` from an up-to-date `main`.

## Implement

Logic in `Packages/PresenterKit`, SwiftUI in the app target. Tests with swift-testing, covering the failure cases the spec names — not only the happy path.

Commit as you go, conventional commits with a scope. Small commits are fine; the squash merge collapses them.

Keep to the issue. If you find something else worth fixing, note it for a separate issue rather than widening this PR.

## Verify

Run `make lint && make test && make build`. All three must pass.

If a criterion cannot be checked in CI — capture, converters — verify it by hand and record what you actually observed, on which hardware.

## PR

Title: a valid conventional commit. **It becomes the squash commit subject**, so it is what lands in `main`'s history.

Body: what changed and why, what you verified and what it said, and `Closes #$ARGUMENTS`. If something is unverified, say which part. An honest gap costs less than a false claim.

If the implementation diverged from an ADR, update the ADR in this same PR.

Show me the PR before creating it.
