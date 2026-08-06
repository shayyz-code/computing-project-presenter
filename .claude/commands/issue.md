---
description: Create a well-formed issue with acceptance criteria, labels and a milestone
argument-hint: <what the issue is about>
---

Create a GitHub issue for: **$ARGUMENTS**

Work out the following before calling `gh`, and ask rather than guess if the answer is not clear from the repo:

**Title** — a valid conventional commit: `type(scope): imperative summary`. Scopes are `slidekit`, `mirrorkit`, `core`, `app`, `docs`, `ci`, `claude`, `repo`. This title will likely become the PR title, and the PR title becomes the squash commit subject, so it lands in `main`'s history permanently.

**Body** — what needs to be true when this is done, and why it matters. Link the spec in `docs/specs/` and any relevant ADR. If it contradicts an accepted ADR, say so explicitly — that is a decision to make, not a detail to bury.

**Acceptance criteria** — a checklist that can be checked, not agreed with. "Handles errors" is not a criterion; "a corrupt file produces `unreadableFile` rather than a crash" is. Include the failure cases, not just the happy path.

**Size** — one PR, reviewable in one sitting. If it does not fit, propose splitting it and say where the seam is.

**Labels** — one `type:` (`feat`, `fix`, `chore`, `spike`) and one `area:` where it applies.

**Milestone** — M0 Foundations, M1 Slides, M2 Mirror, M3 Presenter Shell, or M4 Ship.

If this is a spike, say what question it answers, what would count as an answer, and **which ADR it updates when finished**. A spike whose answer never reaches its ADR was wasted.

Show me the issue before creating it.
