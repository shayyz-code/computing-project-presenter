import AVFoundation
import AppKit
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
    /// Watches for the mirrored window changing shape, which is what a device
    /// rotation looks like from out here.
    private var rotationWatch: Task<Void, Never>?

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
        let capturable = try await capturableWindows()
        return SimulatorWindows.devices(in: capturable).map(SimulatorSource.init(window:))
    }

    /// Every on-system window, as value types.
    ///
    /// Split out so `SourceDiscovery` can build a pickable list without
    /// constructing sources — listing must not start capture, or drawing the
    /// menu would unhide every Simulator.
    public static func capturableWindows() async throws -> [CapturableWindow] {
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

        return content.windows.map {
            CapturableWindow(
                id: $0.windowID,
                title: $0.title,
                bundleIdentifier: $0.owningApplication?.bundleIdentifier,
                width: Int($0.frame.width),
                height: Int($0.frame.height))
        }
    }

    public func start() async throws -> CALayer {
        if let layer { return layer }

        // Before anything else: a hidden Simulator is not drawn, so capture
        // would succeed and deliver nothing.
        Self.revealSimulatorIfHidden()

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
        // Crop off the Simulator's macOS window chrome — its title bar and
        // toolbar buttons. They are noise on a projector and look wrong beside a
        // physical device's drawn chassis. This removes the *window* furniture,
        // not the device bezel, which is drawn inside the window and is exactly
        // what makes the Simulator read as a phone.
        //
        // Derived from the window rather than hardcoded: toolbar height varies
        // with Simulator version, and a fixed inset would silently crop into the
        // device on a version that differs.
        let chromeHeight = Self.windowChromeHeight(for: window)
        if chromeHeight > 0 {
            configuration.sourceRect = CGRect(
                x: 0, y: chromeHeight,
                width: window.frame.width, height: window.frame.height - chromeHeight)
        }
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int((window.frame.height - chromeHeight) * 2)
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

        // Starting successfully does not mean frames are coming. A hidden app —
        // or one on another Space — still yields a valid SCWindow, so the filter
        // and startCapture both succeed while the window server draws nothing.
        // The result is a black pane with no error anywhere, which is the single
        // most expensive failure mode this backend has. Waiting for the first
        // frame is the only reliable way to detect it.
        guard await output.waitForFirstFrame(timeout: Self.firstFrameTimeout) else {
            try? await stream.stopCapture()
            throw MirrorError.captureFailed(
                reason: """
                    Capture started but no frames arrived. The Simulator may be \
                    hidden, minimised, or on another Space — it has to be visible \
                    somewhere for macOS to draw it.
                    """)
        }

        self.stream = stream
        self.output = output
        self.layer = displayLayer
        startWatchingForRotation(configuration: configuration)
        return displayLayer
    }

    /// Follows a rotation by reconfiguring the running stream.
    ///
    /// `updateConfiguration` rather than stop-and-start: restarting drops frames,
    /// re-triggers the capture indicator, and would make a rotation look like a
    /// reconnection to anyone watching.
    ///
    /// Polled, because there is nothing to observe — `SCShareableContent`
    /// publishes no notification when a window resizes. One second is well under
    /// what a rotation takes to notice.
    private func startWatchingForRotation(configuration: SCStreamConfiguration) {
        rotationWatch?.cancel()
        var configured = CGSize(width: configuration.width, height: configuration.height)

        rotationWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let stream = self.stream else { return }

                guard let windows = try? await Self.capturableWindows(),
                    let window = windows.first(where: { $0.id == self.windowID })
                else { continue }

                let wanted = CGSize(width: window.width * 2, height: window.height * 2)
                guard wanted != configured, wanted.width > 0, wanted.height > 0 else { continue }

                let updated = SCStreamConfiguration()
                updated.width = Int(wanted.width)
                updated.height = Int(wanted.height)
                updated.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                updated.queueDepth = 5
                updated.showsCursor = false
                updated.pixelFormat = kCVPixelFormatType_32BGRA
                // Same chrome crop as at start, recomputed for the new shape:
                // a rotated window is a different height, so a remembered inset
                // would crop into the device.
                let chrome = Self.chromeHeight(forWindowHeight: CGFloat(window.height))
                if chrome > 0 {
                    updated.sourceRect = CGRect(
                        x: 0, y: chrome, width: CGFloat(window.width),
                        height: CGFloat(window.height) - chrome)
                    updated.height = Int((CGFloat(window.height) - chrome) * 2)
                }

                try? await stream.updateConfiguration(updated)
                configured = CGSize(width: updated.width, height: updated.height)
            }
        }
    }

    /// Long enough for a slow first frame, short enough that a black pane is
    /// never what the user is left looking at.
    static let firstFrameTimeout: Duration = .seconds(3)

    /// Height of the Simulator's macOS title bar and toolbar, in window points.
    ///
    /// Estimated from the window rather than measured, because `SCWindow`
    /// exposes no content rect. A device window is far taller than it is wide,
    /// so a small fraction of the height is a safe approximation — and it is
    /// clamped so an unusual window (a landscape iPad, say) can never have its
    /// content cropped into.
    static func windowChromeHeight(for window: SCWindow) -> CGFloat {
        chromeHeight(forWindowHeight: window.frame.height)
    }

    /// One calculation, shared by the initial configuration and by rotation, so
    /// the two cannot disagree about where the device starts.
    static func chromeHeight(forWindowHeight height: CGFloat) -> CGFloat {
        guard height > 0 else { return 0 }
        // ~52pt on the measured iPhone 17 window (435x929).
        return min(height * 0.06, 60)
    }

    /// Makes the Simulator visible, because a hidden app is not drawn and so
    /// produces no frames.
    ///
    /// `unhide()` restores its windows **without** activating it, so the
    /// Simulator comes back behind this app rather than stealing focus — which
    /// matters when the point of the app is to be the thing on screen. Asking to
    /// mirror the Simulator is an unambiguous request to see it, so doing this
    /// is carrying out the instruction rather than a surprise.
    private static func revealSimulatorIfHidden() {
        for app in NSRunningApplication.runningApplications(
            withBundleIdentifier: SimulatorWindows.bundleIdentifier)
        where app.isHidden {
            app.unhide()
        }
    }

    public func stop() async {
        rotationWatch?.cancel()
        rotationWatch = nil
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
        rotationWatch?.cancel()
        rotationWatch = nil
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

    private let lock = NSLock()
    private var sawFrame = false

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }

    private var hasFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sawFrame
    }

    private func noteFrame() {
        lock.lock()
        defer { lock.unlock() }
        sawFrame = true
    }

    /// Whether a frame arrived within `timeout`.
    ///
    /// Polled rather than continuation-based on purpose: frames arrive on a
    /// capture queue, and a continuation resumed from there races with the
    /// timeout path. A missed resume would hang `start()` forever, which is a
    /// worse bug than the one being detected.
    func waitForFirstFrame(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if hasFrame { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return hasFrame
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        noteFrame()

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
