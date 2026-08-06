import CoreGraphics
import Foundation
import PDFKit

/// Produces the pixels for one slide, at whatever size and scale the pane asks for.
///
/// The `scale` parameter is the whole point of this protocol. Zoom and Retina both
/// need the same thing — the *same* slide re-rasterised larger, not an existing
/// bitmap stretched — so the caller passes the factor and gets real pixels back.
///
/// Backend-agnostic on purpose. `PDFSlideRenderer` is the implementation today,
/// but ADR-0002 leaves the rendering backend open, and the view layer must not
/// depend on which one it got. A future `OOXMLSlideRenderer` conforms here and
/// nothing above this protocol changes.
public protocol SlideRenderer: Sendable {
    var pageCount: Int { get }

    /// Renders a page into an image of `size * scale` pixels.
    ///
    /// - Parameters:
    ///   - page: zero-based.
    ///   - size: the target size in points — the pane's size, or larger when zoomed.
    ///   - scale: pixels per point. The display's backing scale, times the zoom factor.
    /// - Returns: an image `size.width * scale` by `size.height * scale` pixels.
    /// - Throws: `SlideRenderingError.pageOutOfRange` for an unknown page,
    ///   `SlideRenderingError.renderFailed` if the page could not be drawn.
    func render(page: Int, size: CGSize, scale: CGFloat) throws -> CGImage

    /// Width ÷ height, so the pane can letterbox without rendering first.
    func aspectRatio(page: Int) throws -> CGFloat
}

/// Why a slide could not be rendered.
///
/// Both cases exist so a failure is visible rather than silent. A renderer that
/// returns a blank image for a page it could not draw produces a white rectangle
/// on a projector, which reads as "the slide is empty" — the presenter keeps
/// talking, and nobody knows anything broke.
public enum SlideRenderingError: Error, Equatable, Sendable {
    case pageOutOfRange(page: Int, pageCount: Int)
    case renderFailed(page: Int, reason: String)
}

/// A `SlideRenderer` over a `PDFDocument`.
///
/// Deliberately not built on `PDFView`. `PDFView` owns a scroll view, selection
/// and its own gesture handling, all of which fight the pinch-and-swipe
/// interaction this app needs. Drawing `PDFPage` into a `CGContext` directly
/// keeps that ours, and is what `docs/specs/0001-slide-rendering.md` specifies.
public final class PDFSlideRenderer: SlideRenderer, @unchecked Sendable {
    private let document: PDFDocument
    /// `PDFDocument` is not thread-safe, and rendering is likely to move off the
    /// main actor for prefetch (#18). One lock around every document touch is
    /// cheap next to rasterising a page, and is why `@unchecked Sendable` is
    /// honest here rather than a promise the type cannot keep.
    private let lock = NSLock()

    public init(document: PDFDocument) {
        self.document = document
    }

    public convenience init(url: URL) throws {
        guard let document = PDFDocument(url: url) else {
            throw SlideRenderingError.renderFailed(page: 0, reason: "not a readable PDF")
        }
        self.init(document: document)
    }

    public var pageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return document.pageCount
    }

    public func aspectRatio(page index: Int) throws -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        let bounds = try self.bounds(ofPage: index)
        guard bounds.height > 0 else {
            throw SlideRenderingError.renderFailed(page: index, reason: "page has zero height")
        }
        return bounds.width / bounds.height
    }

    public func render(page index: Int, size: CGSize, scale: CGFloat) throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }

        let page = try self.page(at: index)
        let bounds = try self.bounds(ofPage: index)

        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw SlideRenderingError.renderFailed(page: index, reason: "target size is empty")
        }

        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else {
            throw SlideRenderingError.renderFailed(page: index, reason: "could not create context")
        }

        // Slides are opaque. Without this, a PDF page with no background paints
        // onto transparency and renders black in the pane.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Scale the page's own coordinate space onto the target, rather than
        // scaling the output. This is what keeps text sharp at high zoom instead
        // of magnifying a bitmap — the reason a fixed-resolution image export was
        // rejected in ADR-0002.
        context.saveGState()
        context.scaleBy(
            x: CGFloat(pixelWidth) / bounds.width,
            y: CGFloat(pixelHeight) / bounds.height
        )
        // PDF pages may declare a non-zero origin; drawing without this offset
        // silently crops such a page.
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw SlideRenderingError.renderFailed(page: index, reason: "context produced no image")
        }
        return image
    }

    // MARK: - Bounds checks
    //
    // Both callers hold `lock`, so neither of these takes it.

    private func page(at index: Int) throws -> PDFPage {
        guard index >= 0, index < document.pageCount, let page = document.page(at: index) else {
            throw SlideRenderingError.pageOutOfRange(page: index, pageCount: document.pageCount)
        }
        return page
    }

    private func bounds(ofPage index: Int) throws -> CGRect {
        let bounds = try page(at: index).bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            throw SlideRenderingError.renderFailed(page: index, reason: "page has empty bounds")
        }
        return bounds
    }
}
