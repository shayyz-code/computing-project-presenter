# Agent orchestration

Configuration for [Claude Code](https://claude.com/claude-code) in this repo. Three agents and four commands — deliberately few, because a definition nobody reaches for is overhead that still has to be maintained.

## Agents

| Agent | For |
|---|---|
| [`swift-macos-engineer`](agents/swift-macos-engineer.md) | Implementing features in Swift/SwiftUI |
| [`capture-specialist`](agents/capture-specialist.md) | ScreenCaptureKit, CoreMediaIO, AVFoundation, TCC behaviour |
| [`swift-reviewer`](agents/swift-reviewer.md) | Reviewing diffs before a PR opens |

`capture-specialist` exists because M2's failure modes are specific and unforgiving — permission panes, capture lifecycle, DAL availability — and generic Swift knowledge does not cover them.

## Commands

| Command | Does |
|---|---|
| [`/issue`](commands/issue.md) | Draft an issue with checkable acceptance criteria |
| [`/spec`](commands/spec.md) | Turn an issue into a spec, cross-linked |
| [`/ship`](commands/ship.md) | Branch, implement, verify, open a small PR |
| [`/land`](commands/land.md) | Verify checks, squash-merge, confirm the issue closed |

Together these are the workflow in `docs/CONTRIBUTING.md`, made executable: issue first, then a branch, then a small PR, then a squash merge.

## Permissions

Not configured here. The workflow runs `swift`, `xcodebuild`, `xcrun simctl`, `make`, `soffice` and `gh` repeatedly, and allowlisting those cuts a lot of prompting — but a permission allowlist is a decision about what an agent may do on your machine, so it belongs in your own settings rather than a file committed to a public repo.

Add what you want via `/permissions`, or in `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(swift:*)",
      "Bash(xcodebuild:*)",
      "Bash(xcrun simctl:*)",
      "Bash(gh issue:*)",
      "Bash(gh pr:*)"
    ]
  }
}
```

`settings.local.json` is gitignored.
