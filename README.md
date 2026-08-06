# computing-project-presenter

A macOS app for presenting a software project. Your deck renders on the left; a live iOS screen — Simulator or a USB-connected device — renders on the right. The demo is part of the deck instead of an alt-tab away from it.

> **Status: early.** The foundations are in place; slide rendering and device mirroring are not built yet. See the [milestones](../../milestones) for what is landing when.

## Why

Presenting coursework or a final-year project usually means switching between slides and a running app, losing the thread each time. Putting both in one window removes the switch, and makes a live demo something you can rehearse.

## Building

Requires macOS 15 or later and Xcode 26.

```bash
git clone https://github.com/shayyz-code/computing-project-presenter.git
cd computing-project-presenter
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
