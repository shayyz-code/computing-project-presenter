# ADR-0001: SwiftUI app over SPM modules, with a committed project file

**Status:** Accepted · 2026-08-06

## Context

The app needs an `.app` bundle with entitlements and Info.plist keys, which SwiftPM alone does not produce. So an Xcode project is required. But `.pbxproj` files are notoriously unreviewable and conflict-prone, which is at odds with a workflow built on small PRs and squash merges.

The usual escape is a project generator — XcodeGen or Tuist — where a readable `project.yml` is committed and the `.xcodeproj` is generated and ignored.

## Decision

No generator. One thin app target in a **committed** `Presenter.xcodeproj`, with all logic in SPM library targets under `Packages/PresenterKit`.

The app target uses a `PBXFileSystemSynchronizedRootGroup` (Xcode 16+, `objectVersion = 77`). The project references the *folder*, not each file, so adding a Swift file never edits the project file.

## Consequences

The premise behind generators mostly evaporates: if the `.pbxproj` doesn't change when code changes, there is nothing to conflict over. What remains is one fewer tool to install and no `make generate` step before the project can be opened.

`swift test` runs the whole suite with no Xcode-version coupling, which keeps CI simple and fast.

The cost is real but small: build-setting changes still mean hand-editing or Xcode-editing a `.pbxproj`, and that diff is genuinely unpleasant. Adding a second target — a UI test bundle, say — is where this decision would come under pressure. **If the project file starts changing regularly, revisit rather than tolerate it.**

A large `.pbxproj` diff in a PR is a signal something went wrong, not routine noise.

## Alternatives

**XcodeGen** — solves a problem this structure avoids, at the cost of a Homebrew dependency and a generate step. Reconsider if target count grows.

**SwiftPM executable plus a hand-assembled bundle** — no Xcode project at all, but loses previews, the debugger integration, and straightforward signing. Not worth it for a GUI app.
