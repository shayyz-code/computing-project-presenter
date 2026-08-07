import PresenterCore
import SlideKit
import SwiftUI
import UniformTypeIdentifiers

/// The presenting window's two-pane shape: deck on the left, live device on the
/// right. Both panes are placeholders — M1 fills the left, M2 the right.
struct ContentView: View {
    /// No deck until loading lands (#19, behind the deferred #17/#20). The pane
    /// renders whatever `SlideRenderer` it is given, so wiring a real deck in
    /// later changes only this line.
    @State private var renderer: SlideRenderer?
    @State private var navigator = SlideNavigator(count: 0)
    @State private var slideView = SlideViewState()
    /// Structure read from the `.pptx` itself — slide order and notes. Nil for a
    /// plain PDF, which carries neither.
    @State private var deck: Deck?
    @State private var status: LoadStatus = .idle
    @State private var timer = PresentationTimer()
    @State private var presentation = PresentationController(showsNotesWindowed: true)
    /// Deck, position and notes visibility across launches. One mechanism rather
    /// than a session snapshot plus a separate @AppStorage for notes, which would
    /// be two sources of truth for the same preference.
    private let sessionStore: SessionStore = UserDefaultsSessionStore()
    /// Set when a remembered deck is no longer on disk, so the empty state can
    /// name it instead of starting blank with no explanation.
    @State private var missingDeckPath: String?
    /// The mirror source used last time. Restored so the picker can mark it,
    /// never so it can connect on its own.
    @State private var rememberedSourceID: String?
    @State private var layout = LayoutState()
    /// The file the current deck came from, for saving the session.
    @State private var deckURL: URL?
    /// The uncached renderer, so the thumbnail strip can wrap it in a cache of
    /// its own rather than fighting the pane's over geometry.
    @State private var baseRenderer: SlideRenderer?
    /// Catches space and page up/down — the aliases a presenter and a remote use
    /// that are not menu shortcuts. Routed through the same command type.
    @State private var keyboard = KeyboardNavigation { command in
        NotificationCenter.default.post(
            name: .navigateRequested, object: nil, userInfo: ["command": command.rawValue])
    }

    var body: some View {
        SplitView(layout: layout) {
            if case .converting(let name) = status {
                ConvertingPane(filename: name)
            } else if let renderer {
                VStack(spacing: 0) {
                    SlidePane(
                        renderer: renderer,
                        slideNumber: navigator.position,
                        state: slideView,
                        onNext: { _ = navigator.advance() },
                        onPrevious: { _ = navigator.retreat() }
                    )
                    // The strip and the notes are siblings, so they share one
                    // GlassEffectContainer rather than each sampling its own
                    // backdrop. Independent glass surfaces read as muddy where
                    // they meet, which is exactly what two stacked bars do.
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            // Chrome, so it hides while presenting for the same
                            // reason the notes do: on one display the projector
                            // shows whatever is on screen.
                            if !presentation.mode.isFullscreen, let baseRenderer,
                                navigator.count > 0
                            {
                                ThumbnailStrip(
                                    renderer: baseRenderer,
                                    slideCount: navigator.count,
                                    currentSlide: navigator.position,
                                    onSelect: {
                                        navigator.jump(to: $0); slideView.reset()
                                    }
                                )
                            }
                            // The deck keeps the space; notes take a modest
                            // strip below.
                            if presentation.mode.showsNotes, deck?.hasNotes == true {
                                NotesPane(
                                    deck: deck, slideNumber: navigator.position, timer: timer
                                )
                                .frame(height: 150)
                            }
                        }
                        .padding(12)
                    }
                }
                .frame(minWidth: 320)
            } else {
                PlaceholderPane(
                    title: "Slides",
                    detail: missingDeckPath.map { "Could not find \(($0 as NSString).lastPathComponent)" }
                        ?? "No deck open yet",
                    symbol: "rectangle.on.rectangle"
                ) {
                    Button("Open Deck…") { openDeck() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
        } mirror: {
            MirrorPane(
                rememberedSourceID: rememberedSourceID,
                collapsed: !layout.showsMirror,
                onSourceChanged: { id in
                    rememberedSourceID = id
                    saveSession()
                }
            )
            // Capped, so the deck gets the space. A phone is tall and
            // narrow — at a typical window height it needs about 350pt to
            // fill vertically, and past ~480 the extra width is letterbox
            // rather than phone, because the layer is aspect-fitted.
            // Without a cap, HSplitView hands the slide pane its bare
            // minimum and gives everything else here: the primary content
            // ends up the smallest thing on screen, worst of all in
            // fullscreen where the deck should dominate.
        }
        // Behind everything: the panes' own fills sit on top of it, so only the
        // gaps between them show the desktop.
        .background(WindowBackdrop())
        .background(WindowAccessor { presentation.adopt($0) })
        // Relaxed while presenting: a minimum wider than a small external
        // display would fight the layout rather than protect it.
        .frame(
            minWidth: presentation.mode.isFullscreen ? nil : 900,
            minHeight: presentation.mode.isFullscreen ? nil : 560
        )
        // Native macOS fullscreen does not exit on Escape — it wants ⌃⌘F or the
        // green button. A presenter reaches for Escape, so wire it.
        .onExitCommand {
            if presentation.mode.isFullscreen { presentation.toggleFullscreen() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDeckRequested)) { _ in
            openDeck()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotesRequested)) { _ in
            presentation.toggleNotes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePresentationRequested)) { _ in
            presentation.toggleFullscreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateRequested)) { note in
            guard let raw = note.userInfo?["command"] as? String,
                let command = NavigationCommand(rawValue: raw)
            else { return }
            navigate(command)
        }
        .onAppear { keyboard.start() }
        .onDisappear { keyboard.stop() }
        // Keep the persisted preference in step with the windowed setting, in
        // whichever direction it changed.
        .onChange(of: presentation.mode.showsNotesWindowed) { _, _ in saveSession() }
        .onChange(of: navigator.position) { _, _ in saveSession() }
        .onChange(of: layout.deckFraction) { _, _ in saveSession() }
        .onChange(of: layout.mirrorIsTrailing) { _, _ in saveSession() }
        .onChange(of: layout.collapsed) { _, _ in saveSession() }
        .onReceive(NotificationCenter.default.publisher(for: .swapSidesRequested)) { _ in
            layout.swapSides()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseMirrorRequested)) { _ in
            layout.toggleCollapse(.mirror)
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseDeckRequested)) { _ in
            layout.toggleCollapse(.deck)
        }
        .onAppear { restoreSession() }
        // Drag-and-drop, so a deck can be opened without the file dialog.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let accepted = ["pdf", "pptx"].contains(url.pathExtension.lowercased())
                Task { @MainActor in
                    // A dropped file of the wrong kind gets the same explaining
                    // error as one chosen in the panel, rather than silence.
                    if accepted {
                        open(url, restoringPosition: nil)
                    } else {
                        report(
                            DeckLoadingError.noLoaderAvailable(
                                fileExtension: url.pathExtension), for: url)
                    }
                }
            }
            return true
        }
    }

    /// Reopens the last deck at the last slide.
    ///
    /// Every outcome is handled rather than lumped into "failed to restore",
    /// because a stale session is the normal case for a machine that moves
    /// between a desk and a lecture theatre.
    private func restoreSession() {
        // Layout restores regardless of whether the deck still exists: a moved
        // file should not also reset the window arrangement.
        if let snapshot = sessionStore.load() {
            layout = LayoutState(
                deckFraction: snapshot.deckFraction,
                mirrorIsTrailing: snapshot.mirrorIsTrailing,
                collapsed: snapshot.collapsedPane)
        }

        switch SessionRestoration.from(sessionStore) {
        case .nothingToRestore:
            break

        case .deckMissing(let path, let showsNotes, let sourceID):
            rememberedSourceID = sourceID
            // Restore what still applies and say which file is gone. Starting
            // blank with no explanation would leave the user guessing.
            presentation.mode.showsNotesWindowed = showsNotes
            missingDeckPath = path

        case .restore(let url, let position, let showsNotes, let sourceID):
            presentation.mode.showsNotesWindowed = showsNotes
            rememberedSourceID = sourceID
            // The mirror source is deliberately not reconnected: doing so would
            // unhide the Simulator uninvited and could fire a permission prompt
            // before the user had done anything.
            open(url, restoringPosition: position)
        }
    }

    private func saveSession() {
        sessionStore.save(
            SessionSnapshot(
                deckPath: deckURL?.path,
                slidePosition: navigator.position,
                showsNotes: presentation.mode.showsNotesWindowed,
                mirrorSourceID: rememberedSourceID,
                deckFraction: layout.deckFraction,
                mirrorIsTrailing: layout.mirrorIsTrailing,
                collapsedPane: layout.collapsed))
    }

    /// The one place a navigation command is applied, so the menu and the key
    /// monitor cannot behave differently.
    private func navigate(_ command: NavigationCommand) {
        // A jump lands on a slide the presenter has not seen, so arriving
        // magnified into its corner would be disorienting. Stepping keeps zoom;
        // SlidePane already resets that per slide change.
        if command.apply(to: &navigator), command.isJump {
            slideView.reset()
        }
    }

    /// Opens a `.pdf` directly, or a `.pptx` through the converter chain.
    ///
    /// Drag-and-drop and the thumbnail strip remain #19.
    private func openDeck() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .presentationML]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, restoringPosition: nil)
    }

    /// Opens a deck, optionally jumping to a remembered slide.
    ///
    /// Shared by the open panel and session restore, so a restored deck goes
    /// through exactly the same path as one opened by hand.
    private func open(_ url: URL, restoringPosition position: Int?) {
        missingDeckPath = nil

        // One path for both formats. Branching on the extension here is what let
        // the two drift: .pptx went through a loader and reported emptyDeck and
        // unreadableFile properly, while .pdf skipped it entirely — so a corrupt
        // PDF surfaced a raw rendering error and a page-less one drew a blank
        // pane with no explanation.
        //
        // Progress is only shown for formats that convert. A .pdf opens
        // immediately, and flashing a converting pane at it would be a lie.
        let needsConversion = url.pathExtension.lowercased() != "pdf"
        if needsConversion {
            // Genuinely slow the first time — LibreOffice spent 321s building
            // its user profile on a cold machine (spike #16) — so this must
            // never look like a hang.
            status = .converting(url.lastPathComponent)
        }

        Task {
            do {
                let opened = try await DeckOpener().open(url)
                await MainActor.run {
                    status = .idle
                    show(
                        pdf: opened.renderableURL, deck: opened.deck, source: url,
                        position: position)
                }
            } catch {
                await MainActor.run {
                    status = .idle
                    report(error, for: url)
                }
            }
        }
    }

    private func show(pdf: URL, deck: Deck?, source: URL, position: Int?) {
        do {
            // Wrapped so advancing a slide is a cache hit rather than a fresh
            // rasterisation. Spec 0001 asks for no visible delay after the first
            // page, which a single-image cache could not deliver.
            let base = try PDFSlideRenderer(url: pdf)
            let loaded = CachingSlideRenderer(wrapping: base)
            baseRenderer = base
            renderer = loaded
            // Slide count comes from the deck when there is one: it is read from
            // the .pptx itself, which is authoritative over a converter's output.
            // A saved position from a deck that has since been shortened is
            // clamped here, by SlideNavigator's own construction rule.
            navigator = SlideNavigator(count: deck?.count ?? loaded.pageCount, position: position ?? 1)
            self.deck = deck
            self.deckURL = source
            slideView.reset()
            saveSession()
            // Opening a deck is the start of the talk. start() is idempotent,
            // so reopening does not restart a run already in progress.
            timer.start()
        } catch {
            report(error, for: source)
        }
    }

    /// Names what failed and what to do about it. An empty pane is a bug, per
    /// spec 0001.
    private func report(_ error: Error, for url: URL) {
        let alert = NSAlert()
        alert.messageText = "Could not open \(url.lastPathComponent)"

        switch error {
        case DeckLoadingError.noLoaderAvailable:
            alert.informativeText = """
                Converting a .pptx needs LibreOffice or Keynote installed.

                Install either one, or export the deck to PDF and open that — \
                a PDF needs nothing at all.
                """
        case DeckLoadingError.emptyDeck:
            alert.informativeText = "That deck contains no slides."
        case DeckLoadingError.unreadableFile:
            alert.informativeText = "That file could not be read as a presentation."
        case DeckLoadingError.conversionFailed(_, let reason):
            alert.informativeText = "Conversion failed.\n\n\(reason)"
        case is SlideRenderingError:
            // Reaching here means a file opened as a deck but could not be
            // drawn. Naming it beats printing a Swift enum description.
            alert.informativeText = "That deck opened but could not be rendered."
        default:
            alert.informativeText = "\(error)"
        }
        alert.runModal()
    }
}

/// What the window is doing, so a long conversion is visible rather than silent.
private enum LoadStatus: Equatable {
    case idle
    case converting(String)
}

extension UTType {
    /// `.pptx`. Not in the `UTType` constants, so it is looked up by identifier.
    static let presentationML =
        UTType(
            "org.openxmlformats.presentationml.presentation") ?? .data
}

extension Notification.Name {
    static let openDeckRequested = Notification.Name("openDeckRequested")
    static let toggleNotesRequested = Notification.Name("toggleNotesRequested")
    static let togglePresentationRequested = Notification.Name("togglePresentationRequested")
    static let navigateRequested = Notification.Name("navigateRequested")
    static let swapSidesRequested = Notification.Name("swapSidesRequested")
    static let collapseMirrorRequested = Notification.Name("collapseMirrorRequested")
    static let collapseDeckRequested = Notification.Name("collapseDeckRequested")
}

/// An empty pane: what it is, why it is empty, and an optional way out of that.
///
/// Glass rather than a flat fill, per ADR-0006. The `GlassEffectContainer` is not
/// decoration — sibling glass views each sample their own backdrop and read as
/// muddy where they meet, and the container is what makes them behave as one
/// material.
private struct PlaceholderPane<Action: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder var action: Action

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                action
                    .padding(.top, 6)
            }
            .padding(28)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

extension PlaceholderPane where Action == EmptyView {
    init(title: String, detail: String, symbol: String) {
        self.init(title: title, detail: detail, symbol: symbol) { EmptyView() }
    }
}

/// Shown while a `.pptx` converts.
///
/// Indeterminate on purpose: neither converter reports progress, and a fake
/// determinate bar that sits at 40% for four minutes is worse than an honest
/// spinner. The note about the first conversion is there because that is exactly
/// when someone would otherwise assume the app had hung.
private struct ConvertingPane: View {
    let filename: String

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Converting \(filename)")
                    .font(.headline)
                Text("The first conversion can take a few minutes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
}
