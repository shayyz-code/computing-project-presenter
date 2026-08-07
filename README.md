# Sidecar

**Present your deck and your live app side by side, in one window.** Your slides render on the left; a live iOS screen — Simulator or a USB-connected device — renders on the right. The demo is part of the deck instead of an alt-tab away from it.

> **Status.** Slides, mirroring and the presenter shell are built: `.pdf` and `.pptx` decks, zoom and trackpad navigation, speaker notes with a timer, Simulator and USB device mirroring, fullscreen, and session restore. Remaining work is a multi-display presenter view, an app icon and first-run onboarding — see the [milestones](../../milestones). Distribution is [blocked on an Apple Developer account](docs/adr/0005-distribution.md); build from source in the meantime.

> **Not** Apple's Sidecar, which extends your Mac display to an iPad. This is a presentation tool; the name was chosen deliberately.

## Why

Presenting coursework or a final-year project usually means switching between slides and a running app, losing the thread each time. Putting both in one window removes the switch, and makes a live demo something you can rehearse.

## Installing

**There is no download.** Building from source is the only way to run it: signing a Mac app for distribution needs a paid Apple Developer account, and this project has none — so a downloadable build would be refused by Gatekeeper however carefully it was signed. See [ADR-0005](docs/adr/0005-distribution.md).

**Requires macOS 26 or later**, and Xcode 26 to build. The floor is macOS 26 because the interface uses Liquid Glass, whose APIs start there — see [ADR-0006](docs/adr/0006-design-language.md). On macOS 15 the app will not launch.

```bash
git clone https://github.com/shayyz-code/sidecar.git
cd sidecar
make bootstrap
make run
```

Opening a `.pptx` also needs LibreOffice. A `.pdf` needs nothing at all.

```bash
brew install --cask libreoffice
```

`make help` lists the rest. Logic lives in `Packages/PresenterKit` and runs under `swift test`; the Xcode project is a thin app shell around it.

## What it does

**Slides.** Open a `.pdf` directly, or a `.pptx` converted through LibreOffice. Speaker notes come across with the slides, and the slide view zooms and pans from the trackpad.

**Mirror.** Pick a booted Simulator, an iPhone or iPad connected over USB, or any window on the system. Devices are drawn in a chassis so the demo reads as a phone rather than a floating rectangle.

**Presenting.** Adjustable split, fullscreen, keyboard navigation, an elapsed timer, and speaker notes toggled with ⇧⌘N. The window is translucent while you work and opaque while you present, so a projector never shows your desktop.

**Permissions.** Screen Recording to mirror a Simulator or a window, Camera to mirror a USB device — macOS routes device screens through the camera system. Each is requested when first needed, and denying one shows an explanation with a link to the right Settings pane rather than an empty pane.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). Architecture decisions are recorded in [docs/adr/](docs/adr/) and acceptance criteria in [docs/specs/](docs/specs/).

## License

MIT — see [LICENSE](LICENSE).
