import AppKit
import PresenterCore
import SlideKit
import SwiftUI

/// A horizontal strip of slides, for seeing where you are and jumping.
///
/// **Uses its own renderer instance.** `CachingSlideRenderer` purges when the
/// requested geometry changes, since a display change makes every entry the
/// wrong size — so a strip sharing the pane's renderer would purge the full-size
/// pages on every thumbnail draw and vice versa, thrashing both. Two instances
/// over the same `PDFSlideRenderer` each keep their own geometry and budget;
/// that renderer holds a lock, so concurrent use is safe.
struct ThumbnailStrip: View {
    let renderer: SlideRenderer
    let slideCount: Int
    /// 1-based, matching `SlideNavigator.position`.
    let currentSlide: Int
    let onSelect: (Int) -> Void

    @State private var loader: ThumbnailLoader

    init(renderer: SlideRenderer, slideCount: Int, currentSlide: Int, onSelect: @escaping (Int) -> Void) {
        self.renderer = renderer
        self.slideCount = slideCount
        self.currentSlide = currentSlide
        self.onSelect = onSelect
        _loader = State(initialValue: ThumbnailLoader(renderer: renderer))
    }

    private static let height: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    // `1...slideCount` traps on an empty deck, which is a real
                    // state before a file is opened.
                    ForEach(Array(1...max(slideCount, 1)), id: \.self) { number in
                        // A Button rather than onTapGesture: it is focusable,
                        // activates under VoiceOver and the keyboard, and takes
                        // synthetic clicks — a bare tap gesture did none of
                        // those, which is why clicking a thumbnail did nothing.
                        Button {
                            onSelect(number)
                        } label: {
                            ThumbnailCell(
                                image: loader.images[number],
                                number: number,
                                isCurrent: number == currentSlide,
                                height: Self.height
                            )
                        }
                        .buttonStyle(.plain)
                        .id(number)
                        .task { await loader.load(slide: number, height: Self.height) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: currentSlide) { _, new in
                // Keep the current slide visible: navigating by keyboard would
                // otherwise leave the strip showing somewhere else entirely.
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .onAppear { proxy.scrollTo(currentSlide, anchor: .center) }
        }
        .frame(height: Self.height + 16)
        .glassEffect(in: .rect(cornerRadius: 12))
    }
}

private struct ThumbnailCell: View {
    let image: CGImage?
    let number: Int
    let isCurrent: Bool
    let height: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // A placeholder of the right shape, so the strip does not reflow
                // as thumbnails arrive.
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isCurrent ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isCurrent ? 2.5 : 1)
        }
        .help("Slide \(number)")
        .accessibilityLabel("Slide \(number)")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }
}

/// Renders thumbnails off the main thread and publishes them as they arrive.
@MainActor
@Observable
final class ThumbnailLoader {
    private(set) var images: [Int: CGImage] = [:]
    private let renderer: SlideRenderer
    private var inFlight: Set<Int> = []

    init(renderer: SlideRenderer) {
        // Wrapped in its own cache with a small budget: thumbnails are tiny, and
        // a whole deck of them costs far less than a couple of full-size pages.
        self.renderer = CachingSlideRenderer(wrapping: renderer, budgetBytes: 32 << 20)
    }

    /// Renders one thumbnail if it is not already loaded or loading.
    func load(slide number: Int, height: CGFloat) async {
        guard images[number] == nil, !inFlight.contains(number) else { return }
        let page = number - 1
        guard page >= 0, page < renderer.pageCount else { return }

        inFlight.insert(number)
        defer { inFlight.remove(number) }

        let aspect = (try? renderer.aspectRatio(page: page)) ?? 16.0 / 9.0
        let size = CGSize(width: height * aspect, height: height)
        let renderer = self.renderer

        // Off the main actor: sixteen rasterisations on it would stall the first
        // frame of the strip and any keypress landing at the same moment.
        let image = await Task.detached(priority: .utility) {
            try? renderer.render(page: page, size: size, scale: 2)
        }.value

        if let image { images[number] = image }
    }
}
