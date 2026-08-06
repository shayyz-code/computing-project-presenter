import PresenterCore
import SlideKit
import SwiftUI

/// The presenting window's two-pane shape: deck on the left, live device on the
/// right. Both panes are placeholders — M1 fills the left, M2 the right.
struct ContentView: View {
    /// No deck until loading lands (#19, behind the deferred #17/#20). The pane
    /// renders whatever `SlideRenderer` it is given, so wiring a real deck in
    /// later changes only this line.
    @State private var renderer: SlideRenderer?
    @State private var navigator = SlideNavigator(count: 0)
    @State private var slideView = SlideViewState()

    var body: some View {
        HSplitView {
            if let renderer {
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

    /// Minimal `.pdf` open, so the pane is reachable.
    ///
    /// Not the deck-loading story — that is #19, with `.pptx` conversion, drag
    /// and drop, progress and error states. This is the smallest thing that makes
    /// the slide pane usable rather than unreachable code.
    private func openDeck() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let loaded = try PDFSlideRenderer(url: url)
            renderer = loaded
            navigator = SlideNavigator(count: loaded.pageCount)
            slideView.reset()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open that deck"
            // Say what happened rather than showing an empty pane, per spec 0001.
            alert.informativeText = "\(url.lastPathComponent) is not a readable PDF."
            alert.runModal()
        }
    }
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

#Preview {
    ContentView()
}
