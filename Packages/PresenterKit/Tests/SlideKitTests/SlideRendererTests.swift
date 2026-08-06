import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import SlideKit

/// Builds a PDF in memory rather than committing a fixture.
///
/// Deliberate: this keeps the renderer tests runnable in CI with no fixture file
/// and no converter, and lets a test state the page geometry it needs instead of
/// asserting against whatever a checked-in file happens to contain.
private func makePDF(pages: [CGSize]) throws -> PDFDocument {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        throw TestPDFError.couldNotBuild
    }
    var firstBox = CGRect(origin: .zero, size: pages.first ?? CGSize(width: 100, height: 100))
    guard let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else {
        throw TestPDFError.couldNotBuild
    }
    for size in pages {
        let box = CGRect(origin: .zero, size: size)
        // kCGPDFContextMediaBox wants a CFData wrapping a CGRect. An NSValue is
        // accepted by the CFDictionary and then silently ignored, so every page
        // inherits the document box — which made a differing-page-size test pass
        // for the wrong reason until it was checked.
        let boxData = withUnsafeBytes(of: box) { raw in
            CFDataCreate(nil, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }
        context.beginPDFPage([kCGPDFContextMediaBox as String: boxData as Any] as CFDictionary)
        // Something visible, so "did it draw" is distinguishable from "blank".
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: box.width / 2, height: box.height / 2))
        context.endPDFPage()
    }
    context.closePDF()
    guard let document = PDFDocument(data: data as Data) else { throw TestPDFError.couldNotBuild }
    return document
}

private enum TestPDFError: Error { case couldNotBuild }

@Suite("PDFSlideRenderer")
struct SlideRendererTests {

    @Test("Reports the document's page count")
    func pageCount() throws {
        let renderer = PDFSlideRenderer(
            document: try makePDF(pages: [
                CGSize(width: 640, height: 480), CGSize(width: 640, height: 480),
                CGSize(width: 640, height: 480),
            ]))
        #expect(renderer.pageCount == 3)
    }

    @Test("Aspect ratio comes from the page box")
    func aspectRatio() throws {
        let renderer = PDFSlideRenderer(
            document: try makePDF(pages: [
                CGSize(width: 1600, height: 900),  // 16:9
                CGSize(width: 1024, height: 768),  // 4:3
            ]))
        #expect(abs(try renderer.aspectRatio(page: 0) - 16.0 / 9.0) < 0.001)
        #expect(abs(try renderer.aspectRatio(page: 1) - 4.0 / 3.0) < 0.001)
    }

    @Test("Scale multiplies pixel dimensions, so zoom re-rasterises")
    func scaleProducesMorePixels() throws {
        // The criterion the whole protocol exists for: the same slide at scale 2
        // must be twice the pixels, not the same pixels stretched. This is what a
        // fixed-resolution image export could not do.
        let renderer = PDFSlideRenderer(document: try makePDF(pages: [CGSize(width: 800, height: 600)]))
        let size = CGSize(width: 400, height: 300)

        let at1 = try renderer.render(page: 0, size: size, scale: 1)
        let at2 = try renderer.render(page: 0, size: size, scale: 2)
        let at4 = try renderer.render(page: 0, size: size, scale: 4)

        #expect(at1.width == 400 && at1.height == 300)
        #expect(at2.width == 800 && at2.height == 600)
        #expect(at4.width == 1600 && at4.height == 1200)
    }

    @Test("Rendering actually draws the page rather than returning blank")
    func drawsContent() throws {
        // Guards the failure that is invisible on a projector: a renderer which
        // returns a correctly sized white image looks like an empty slide.
        let renderer = PDFSlideRenderer(document: try makePDF(pages: [CGSize(width: 200, height: 200)]))
        let image = try renderer.render(page: 0, size: CGSize(width: 200, height: 200), scale: 1)

        let context = CGContext(
            data: nil, width: Int(image.width), height: Int(image.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let pixels = context?.data else {
            Issue.record("could not read rendered pixels")
            return
        }

        // The fixture fills the lower-left quadrant black; sample inside it.
        let bytesPerRow = context?.bytesPerRow ?? 0
        let sampleX = 50
        let sampleY = image.height - 50  // CGContext origin is bottom-left
        let offset = sampleY * bytesPerRow + sampleX * 4
        let byte = pixels.load(fromByteOffset: offset + 1, as: UInt8.self)
        #expect(byte < 128, "expected drawn (dark) content, got \(byte)")
    }

    @Test("An out-of-range page throws instead of trapping")
    func outOfRange() throws {
        let renderer = PDFSlideRenderer(document: try makePDF(pages: [CGSize(width: 100, height: 100)]))
        let size = CGSize(width: 100, height: 100)

        #expect(throws: SlideRenderingError.pageOutOfRange(page: 5, pageCount: 1)) {
            try renderer.render(page: 5, size: size, scale: 1)
        }
        #expect(throws: SlideRenderingError.pageOutOfRange(page: -1, pageCount: 1)) {
            try renderer.render(page: -1, size: size, scale: 1)
        }
        #expect(throws: SlideRenderingError.pageOutOfRange(page: 5, pageCount: 1)) {
            try renderer.aspectRatio(page: 5)
        }
    }

    @Test("An empty target size throws rather than producing a zero-pixel image")
    func emptySize() throws {
        let renderer = PDFSlideRenderer(document: try makePDF(pages: [CGSize(width: 100, height: 100)]))
        #expect(throws: SlideRenderingError.self) {
            try renderer.render(page: 0, size: .zero, scale: 1)
        }
        // A pane can legitimately be laid out at zero width for one frame during
        // a window resize; that must not crash the app.
        #expect(throws: SlideRenderingError.self) {
            try renderer.render(page: 0, size: CGSize(width: 0, height: 300), scale: 2)
        }
    }

    @Test("A non-PDF URL throws rather than yielding an empty renderer")
    func badURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-pdf-\(UUID().uuidString).pdf")
        try Data("plain text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: SlideRenderingError.self) {
            try PDFSlideRenderer(url: url)
        }
    }
}
