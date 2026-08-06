import AVFoundation
import CoreMedia
import Foundation
import QuartzCore
import ScreenCaptureKit

/// Mirrors a booted iOS Simulator by capturing its window.
///
/// A Simulator is an ordinary macOS window, so ScreenCaptureKit is the whole
/// mechanism — no CoreMediaIO, no device pairing. That makes this the simplest
/// of the three backends and the reason it is built first: it proves the
/// layer-vending shape in ADR-0003 before the device path (#25) needs it.
@MainActor
public final class SimulatorSource: MirrorSource {
    public let id: String
    public let displayName: String
    public let kind: MirrorSourceKind = .simulator

    private let windowID: CGWindowID
    private var stream: SCStream?
    private var layer: AVSampleBufferDisplayLayer?
    private var output: StreamOutput?

    /// Called when capture stops on its own — the Simulator quit, or the system
    /// stopped the stream. The pane needs this to show a reconnect state rather
    /// than a frozen last frame.
    public var onStopped: ((MirrorError) -> Void)?

    public init(window: CapturableWindow) {
        self.windowID = window.id
        self.id = "simulator-\(window.id)"
        self.displayName = SimulatorWindows.displayName(for: window)
    }

    /// Every booted Simulator currently on screen.
    ///
    /// Returns an empty array when none is running — that is a normal state, not
    /// an error, and booting one later should just start working. Only a genuine
    /// failure (notably denied consent) throws.
    public static func availableSources() async throws -> [SimulatorSource] {
        let content: SCShareableContent
        do {
            // onScreenWindowsOnly: false is deliberate and load-bearing. With
            // `true`, a Simulator sitting behind another window or on another
            // Space is absent from the list entirely — measured: 0 simulator
            // windows with `true`, 6 with `false`, while the Simulator was
            // running the whole time. The user would be told "no Simulator
            // running", which is both false and unactionable. SCK captures a
            // window independently of occlusion, so there is no reason to
            // require it be frontmost.
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            throw MirrorError.from(error, kind: .simulator)
        }

        let capturable = content.windows.map {
            CapturableWindow(
                id: $0.windowID,
                title: $0.title,
                bundleIdentifier: $0.owningApplication?.bundleIdentifier,
                width: Int($0.frame.width),
                height: Int($0.frame.height))
        }
        return SimulatorWindows.devices(in: capturable).map(SimulatorSource.init(window:))
    }

    public func start() async throws -> CALayer {
        if let layer { return layer }

        // Re-fetch rather than holding the SCWindow from discovery: a window
        // captured from a stale list may already be gone, and SCStream's error
        // for that is far less clear than checking here.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            throw MirrorError.from(error, kind: .simulator)
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw MirrorError.sourceDisappeared(id: id)
        }

        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect

        let configuration = SCStreamConfiguration()
        // Capture at the window's own pixel size. Scaling belongs to the pane,
        // which knows how much room it has; scaling here would throw away detail
        // the pane might want.
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        // A macOS cursor floating over a mirrored phone reads as a rendering
        // bug, not as a cursor.
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let output = StreamOutput(layer: displayLayer)
        output.onStopped = { [weak self] error in
            Task { @MainActor in self?.handleStreamStopped(error) }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(
                output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "mirrorkit.simulator"))
            try await stream.startCapture()
        } catch {
            throw MirrorError.from(error, kind: .simulator)
        }

        self.stream = stream
        self.output = output
        self.layer = displayLayer
        return displayLayer
    }

    public func stop() async {
        // Order matters: stop the stream before dropping the layer, or the macOS
        // capture indicator lingers after the source is switched away — which
        // users read as the app still watching their screen.
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        output = nil
        layer = nil
    }

    private func handleStreamStopped(_ error: MirrorError) {
        stream = nil
        output = nil
        layer = nil
        onStopped?(error)
    }
}

/// Receives frames and stream-level failures.
///
/// A separate object because `SCStream` holds its delegate and output weakly in
/// places and strongly in others; keeping it off `SimulatorSource` avoids a
/// retain cycle through the stream. `@unchecked Sendable` is honest rather than
/// convenient: the only mutable state is the layer, and frames arrive serialised
/// on one queue.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let layer: AVSampleBufferDisplayLayer
    var onStopped: ((MirrorError) -> Void)?

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Frames arrive whether or not anything changed on screen; SCK marks the
        // ones with no new content. Enqueuing those wastes work and can stall the
        // renderer's queue.
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw), status == .complete
        else { return }

        // Mark the frame for immediate display. Without this the renderer waits
        // on a control timebase that was never set, so buffers are accepted and
        // then never presented -- the pane stays black while capture is working
        // perfectly. Setting a timebase is the alternative; for a live mirror
        // there is nothing to synchronise against, so immediate is both simpler
        // and more correct.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: true) as? [CFMutableDictionary],
            let first = attachments.first
        {
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        if layer.sampleBufferRenderer.status == .failed {
            layer.sampleBufferRenderer.flush()
        }
        layer.sampleBufferRenderer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?(MirrorError.from(error, kind: .simulator))
    }
}
