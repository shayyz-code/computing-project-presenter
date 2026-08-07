import AVFoundation
import CoreMedia
import Foundation
import QuartzCore
import ScreenCaptureKit

/// Mirrors any window the user picks.
///
/// Also ADR-0003's fallback route: if the CoreMediaIO device path is ever
/// unavailable, a user can open QuickTime with their phone as its movie-recording
/// source and mirror *that* window through here.
///
/// **Uses `SCContentSharingPicker` rather than a hand-built filter.** That is not
/// only for the UI. On macOS 26 an `SCContentFilter` constructed directly
/// triggers an additional consent prompt — *"requesting to bypass the system
/// private window picker and directly access your screen and audio"* — which the
/// picker, being the sanctioned path, does not. `SimulatorSource` still builds
/// its filter directly on purpose: making a presenter choose their Simulator from
/// a system sheet on every connect would be worse than one extra grant.
@MainActor
public final class WindowSource: NSObject, MirrorSource {
    public let id: String
    public private(set) var displayName: String
    public let kind: MirrorSourceKind = .window

    private var stream: SCStream?
    private var layer: AVSampleBufferDisplayLayer?
    private var output: WindowStreamOutput?
    private var pickerObserver: PickerObserver?

    public var onStopped: ((MirrorError) -> Void)?

    public override init() {
        self.id = SourceCatalogue.windowPickerIdentifier
        self.displayName = "Choose Window…"
        super.init()
    }

    /// Presents the system picker and mirrors whatever is chosen.
    ///
    /// The picker is modal to the user but not to us: the choice arrives through
    /// an observer callback, so this waits for it rather than returning a source
    /// that is not yet pointed at anything.
    public func start() async throws -> CALayer {
        if let layer { return layer }

        let filter = try await presentPicker()
        return try await beginCapture(with: filter)
    }

    private func presentPicker() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        let observer = PickerObserver()
        pickerObserver = observer

        picker.add(observer)
        picker.isActive = true
        // Windows only. A whole display would put this app's own window inside
        // its own mirror, which recurses visually and is never what was wanted.
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        picker.configuration = configuration
        picker.present()

        defer {
            picker.remove(observer)
            picker.isActive = false
            pickerObserver = nil
        }

        switch await observer.awaitSelection() {
        case .picked(let filter, let name):
            displayName = name ?? "Window"
            return filter
        case .cancelled:
            // Not an error state. Backing out of a picker is a decision, and it
            // should leave the pane as it was rather than showing a failure.
            throw MirrorError.sourceDisappeared(id: id)
        case .failed(let error):
            throw MirrorError.from(error, kind: .window)
        }
    }

    private func beginCapture(with filter: SCContentFilter) async throws -> CALayer {
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect

        let configuration = SCStreamConfiguration()
        let size = filter.contentRect
        configuration.width = Int(size.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(size.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let output = WindowStreamOutput(layer: displayLayer)
        output.onStopped = { [weak self] error in
            Task { @MainActor in self?.handleStopped(error) }
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(
                output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "mirrorkit.window"))
            try await stream.startCapture()
        } catch {
            throw MirrorError.from(error, kind: .window)
        }

        // Same watchdog as the Simulator path, for the same reason: a window
        // that is minimised or on another Space yields a valid filter and a
        // stream that starts cleanly, then delivers nothing at all.
        guard await output.waitForFirstFrame(timeout: SimulatorSource.firstFrameTimeout) else {
            try? await stream.stopCapture()
            throw MirrorError.captureFailed(
                reason: """
                    Capture started but no frames arrived. The window may be \
                    minimised or on another Space — it has to be visible \
                    somewhere for macOS to draw it.
                    """)
        }

        self.stream = stream
        self.output = output
        self.layer = displayLayer
        return displayLayer
    }

    public func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        output = nil
        layer = nil
    }

    private func handleStopped(_ error: MirrorError) {
        stream = nil
        output = nil
        layer = nil
        onStopped?(error)
    }
}

/// Bridges the picker's delegate callbacks to an `async` result.
private final class PickerObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
    /// `@unchecked Sendable` because `SCContentFilter` and `Error` are not
    /// annotated, and this is a one-shot handoff from the picker's callback to a
    /// single awaiting caller — the lock below is what makes that safe.
    enum Outcome: @unchecked Sendable {
        case picked(SCContentFilter, String?)
        case cancelled
        case failed(Error)
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var pending: Outcome?

    func awaitSelection() async -> Outcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            // The callback can land before the continuation is installed, so a
            // result that already arrived is delivered rather than waited for —
            // otherwise this hangs forever on a fast pick.
            if let pending {
                self.pending = nil
                lock.unlock()
                continuation.resume(returning: pending)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func deliver(_ outcome: Outcome) {
        lock.lock()
        guard let continuation else {
            pending = outcome
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: outcome)
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        deliver(.picked(filter, nil))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        deliver(.cancelled)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        deliver(.failed(error))
    }
}

/// Receives frames for a picked window.
private final class WindowStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
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
        lock.lock()
        sawFrame = true
        lock.unlock()

        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw), status == .complete
        else { return }

        if layer.sampleBufferRenderer.status == .failed {
            layer.sampleBufferRenderer.flush()
        }
        layer.sampleBufferRenderer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?(MirrorError.from(error, kind: .window))
    }
}
