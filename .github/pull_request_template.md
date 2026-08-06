<!--
PR title must be a valid conventional commit — type(scope): summary.
The repo squash-merges with PR_TITLE as the commit subject, so this
title is what lands in main's history permanently.

Scopes: slidekit, mirrorkit, core, app, docs, ci, claude, repo
-->

## What and why

## Verification

<!--
What you ran and what it said. "make test — 11 passing" is useful;
"should work" is not. If a criterion cannot run in CI (capture,
converters), say how you verified it by hand and on what hardware.
If something is unverified, say which part — an honest gap costs less
than a false claim.
-->

- [ ] `make lint`
- [ ] `make test`
- [ ] `make build`

## Notes

<!--
Anything a reviewer would otherwise have to work out: deviations from
the issue, an ADR this contradicts (update it in this PR), a decision
you'd like a second opinion on.
-->

Closes #
