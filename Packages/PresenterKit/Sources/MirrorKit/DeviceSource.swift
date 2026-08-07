import AVFoundation
import Foundation
import QuartzCore

/// Mirrors a USB-connected iOS device.
///
/// CoreMediaIO publishes the device's screen as an `AVCaptureDevice`, so this is
/// an `AVCaptureSession` vending an `AVCaptureVideoPreviewLayer` — which is why
/// ADR-0003 chose a layer-vending protocol rather than unifying on
/// `CMSampleBuffer`: this path gets its layer almost for free.
///
/// Verified against an iPhone 13 Pro Max on iOS 27 in spike #22: no private
/// entitlement, 13–40 fps, 1284x2778 device-native.
@MainActor
public final class DeviceSource: MirrorSource {
    public let id: String
    public let displayName: String
    public let kind: MirrorSourceKind = .device

    private let uniqueID: String
    private var session: AVCaptureSession?
    private var layer: AVCaptureVideoPreviewLayer?
    private var observers: [NSObjectProtocol] = []

    public var onStopped: ((MirrorError) -> Void)?

    public init(device: CapturableDevice) {
        self.uniqueID = device.uniqueID
        self.id = "device-\(device.uniqueID)"
        self.displayName = device.localizedName
    }

    /// Every connected iOS device screen.
    ///
    /// Waits for publication rather than enumerating once. Returns empty when no
    /// device is attached — a normal state, not an error.
    /// Every published capture device, as value types.
    ///
    /// Sets the DAL property first, because the iPhone's screen is not published
    /// at all until it is. Synchronous and non-throwing: an empty result means
    /// nothing is attached, which is a normal state rather than an error.
    public static func capturableDevices() -> [CapturableDevice] {
        DeviceDiscovery.allowScreenCaptureDevices()
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: DeviceDiscovery.deviceTypes, mediaType: nil, position: .unspecified
        ).devices.map(CapturableDevice.init)
    }

    public static func availableSources() async throws -> [DeviceSource] {
        DeviceDiscovery.allowScreenCaptureDevices()

        // One retained session, not a new one per poll: rebuilding it discards
        // whatever observation state it accumulates, which is part of why the
        // spike saw intermittent results.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: DeviceDiscovery.deviceTypes, mediaType: nil, position: .unspecified)

        let deadline = ContinuousClock.now + DeviceDiscovery.publicationTimeout
        while ContinuousClock.now < deadline {
            let screens = DeviceDiscovery.screens(in: discovery.devices.map(CapturableDevice.init))
            if !screens.isEmpty { return screens.map(DeviceSource.init(device:)) }
            // Servicing the run loop matters: publication is delivered by
            // notification, and a thread that only sleeps never sees it.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(200))
        }
        return []
    }

    public func start() async throws -> CALayer {
        if let layer { return layer }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw MirrorError.permissionDenied(.device)
            }
        case .denied, .restricted:
            // Camera, not Screen Recording. Different pane, different fix.
            throw MirrorError.permissionDenied(.device)
        @unknown default:
            throw MirrorError.permissionDenied(.device)
        }

        DeviceDiscovery.allowScreenCaptureDevices()
        guard let device = Self.captureDevice(uniqueID: uniqueID) else {
            throw MirrorError.sourceDisappeared(id: id)
        }

        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw MirrorError.captureFailed(reason: "the device refused a capture input")
            }
            session.addInput(input)
        } catch let error as MirrorError {
            throw error
        } catch {
            throw MirrorError.captureFailed(reason: error.localizedDescription)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect

        // Unplugging must surface a reconnect state. A frozen last frame is
        // worse than an error: the presenter keeps talking to a dead image.
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handleStopped(.sourceDisappeared(id: self.id))
                }
            })
        observers.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
            ) { [weak self] note in
                // Read the description out of the notification *here*, before
                // crossing into the actor. A Notification is not Sendable, and
                // carrying one across the boundary is a real race rather than a
                // compiler technicality.
                let reason =
                    (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                    ?? "the capture session failed"
                MainActor.assumeIsolated {
                    self?.handleStopped(.captureFailed(reason: reason))
                }
            })

        session.startRunning()

        self.session = session
        self.layer = preview
        return preview
    }

    public func stop() async {
        session?.stopRunning()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        session = nil
        layer = nil
    }

    private func handleStopped(_ error: MirrorError) {
        session?.stopRunning()
        session = nil
        layer = nil
        onStopped?(error)
    }

    private static func captureDevice(uniqueID: String) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: DeviceDiscovery.deviceTypes, mediaType: nil, position: .unspecified
        ).devices.first { $0.uniqueID == uniqueID }
    }
}
