# Sidecar

**Present your deck and your live app side by side, in one window.** Your slides render on the left; a live iOS screen — Simulator or a USB-connected device — renders on the right. The demo is part of the deck instead of an alt-tab away from it.

> **Status.** Slides, mirroring and the presenter shell are built: `.pdf` and `.pptx` decks, zoom and trackpad navigation, speaker notes with a timer, Simulator and USB device mirroring, fullscreen, and session restore. Remaining work is distribution — see the [milestones](../../milestones).

> **Not** Apple's Sidecar, which extends your Mac display to an iPad. This is a presentation tool; the name was chosen deliberately.

## Why

Presenting coursework or a final-year project usually means switching between slides and a running app, losing the thread each time. Putting both in one window removes the switch, and makes a live demo something you can rehearse.

## Building

**Requires macOS 26 or later**, and Xcode 26 to build. The floor is macOS 26 because the interface uses Liquid Glass, whose APIs start there — see [ADR-0006](docs/adr/0006-design-language.md). On macOS 15 the app will not launch.

```bash
git clone https://github.com/shayyz-code/sidecar.git
cd sidecar
make bootstrap
make run
```

`make help` lists the rest. Logic lives in `Packages/PresenterKit` and runs under `swift test`; the Xcode project is a thin app shell around it.

## Planned behaviour

**Slides.** Open a `.pdf` directly, or a `.pptx` converted through LibreOffice when installed, otherwise Keynote. Speaker notes come across with the slides.

**Mirror.** Pick a booted Simulator, a connected iPhone or iPad over USB, or any window on the system.

**Presenting.** Adjustable split, fullscreen, keyboard navigation, an elapsed timer, and speaker notes on a second display.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). Architecture decisions are recorded in [docs/adr/](docs/adr/) and acceptance criteria in [docs/specs/](docs/specs/).

## License

MIT — see [LICENSE](LICENSE).
