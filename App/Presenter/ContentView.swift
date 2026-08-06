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

    var body: some View {
        HSplitView {
            if case .converting(let name) = status {
                ConvertingPane(filename: name)
            } else if let renderer {
                SlidePane(
                    renderer: renderer,
                    slideNumber: navigator.position,
                    state: slideView,
                    onNext: { _ = navigator.advance() },
                    onPrevious: { _ = navigator.retreat() }
                )
                .frame(minWidth: 320)
            } else {
                PlaceholderPane(
                    title: "Slides",
                    detail: "No deck open yet",
                    symbol: "rectangle.on.rectangle"
                ) {
                    Button("Open Deck…") { openDeck() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
            PlaceholderPane(
                title: "Device",
                detail: "Mirror a simulator or a connected iPhone",
                symbol: "iphone.gen3"
            )
        }
        .frame(minWidth: 900, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: .openDeckRequested)) { _ in
            openDeck()
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

        if url.pathExtension.lowercased() == "pdf" {
            show(pdf: url, deck: nil, source: url)
            return
        }

        // Conversion is genuinely slow the first time — LibreOffice spent 321s
        // building its user profile on a cold machine (spike #16) — so this must
        // never look like a hang.
        status = .converting(url.lastPathComponent)
        Task {
            do {
                let loader = PPTXDeckLoader()
                let deck = try await loader.load(url)
                let pdf = try await loader.convertedPDF(for: url)
                await MainActor.run {
                    status = .idle
                    show(pdf: pdf, deck: deck, source: url)
                }
            } catch {
                await MainActor.run {
                    status = .idle
                    report(error, for: url)
                }
            }
        }
    }

    private func show(pdf: URL, deck: Deck?, source: URL) {
        do {
            let loaded = try PDFSlideRenderer(url: pdf)
            renderer = loaded
            // Slide count comes from the deck when there is one: it is read from
            // the .pptx itself, which is authoritative over a converter's output.
            navigator = SlideNavigator(count: deck?.count ?? loaded.pageCount)
            self.deck = deck
            slideView.reset()
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
