import Foundation

/// A source the user can pick, before anything is connected.
///
/// Separate from `MirrorSource` because listing must not start capture: building
/// the menu would otherwise unhide every Simulator and prompt for permissions
/// just to draw it.
public struct MirrorSourceDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: MirrorSourceKind

    public init(id: String, name: String, kind: MirrorSourceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Builds the list of pickable sources.
///
/// The list-building is a pure function over the value types `SimulatorWindows`
/// and `DeviceDiscovery` already vend, so identity, ordering and diffing are all
/// testable with no capture, no hardware and no TCC consent.
public enum SourceCatalogue {

    /// Identity that survives a source disappearing and coming back.
    ///
    /// **Not the `CGWindowID`.** Quit a Simulator and relaunch it and the window
    /// id changes, so a remembered selection would silently stop matching — and
    /// session restore stores exactly this id. The device name in the window
    /// title survives a relaunch, so it is what identity is built from.
    public static func identifier(forSimulatorNamed name: String) -> String {
        "simulator-\(name)"
    }

    public static func identifier(forDeviceWithUniqueID uniqueID: String) -> String {
        // Already stable across unplug and replug.
        "device-\(uniqueID)"
    }

    /// The id of the "pick any window" entry, which is a mode rather than a
    /// particular window — the window is only chosen once the system picker runs.
    public static let windowPickerIdentifier = "window-picker"

    /// Every pickable source, simulators first, then devices, then the window
    /// picker.
    ///
    /// Ordered rather than incidental: the Simulator is the common case during
    /// development, and the picker is a deliberate action so it belongs last.
    public static func sources(
        windows: [CapturableWindow], devices: [CapturableDevice]
    ) -> [MirrorSourceDescriptor] {
        var result: [MirrorSourceDescriptor] = []

        for window in SimulatorWindows.devices(in: windows) {
            let name = SimulatorWindows.displayName(for: window)
            let id = identifier(forSimulatorNamed: name)
            // Two windows of the same simulator would otherwise appear twice.
            guard !result.contains(where: { $0.id == id }) else { continue }
            result.append(MirrorSourceDescriptor(id: id, name: name, kind: .simulator))
        }

        for device in DeviceDiscovery.screens(in: devices) {
            result.append(
                MirrorSourceDescriptor(
                    id: identifier(forDeviceWithUniqueID: device.uniqueID),
                    name: device.localizedName, kind: .device))
        }

        result.append(
            MirrorSourceDescriptor(
                id: windowPickerIdentifier, name: "Choose Window…", kind: .window))
        return result
    }

    /// What changed between two lists.
    ///
    /// Used to keep a selection alive across a refresh: a source that vanished
    /// for one poll and returned must not clear the user's choice.
    public static func changes(
        from old: [MirrorSourceDescriptor], to new: [MirrorSourceDescriptor]
    ) -> (appeared: [MirrorSourceDescriptor], disappeared: [MirrorSourceDescriptor]) {
        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(new.map(\.id))
        return (
            appeared: new.filter { !oldIDs.contains($0.id) },
            disappeared: old.filter { !newIDs.contains($0.id) }
        )
    }

    /// Whether a remembered selection is still available.
    public static func contains(_ id: String?, in sources: [MirrorSourceDescriptor]) -> Bool {
        guard let id else { return false }
        return sources.contains { $0.id == id }
    }
}

/// Keeps the pickable list current while the app is running.
@MainActor
@Observable
public final class SourceDiscovery {
    public private(set) var sources: [MirrorSourceDescriptor] = []
    /// Non-nil when the last refresh failed for a reason the user can act on —
    /// denied Screen Recording, most likely.
    public private(set) var lastError: MirrorError?

    private var monitor: Task<Void, Never>?

    /// How often to re-enumerate.
    ///
    /// Polled rather than observed, because there is nothing to observe:
    /// `SCShareableContent` publishes no change notification, and
    /// `AVCaptureDevice.wasConnectedNotification` covers only the device half.
    /// Two seconds meets spec 0002's "within ~2s of booting" without spinning.
    public static let refreshInterval: Duration = .seconds(2)

    public init() {}

    /// Re-enumerates once.
    public func refresh() async {
        do {
            let windows = try await SimulatorSource.capturableWindows()
            let devices = DeviceSource.capturableDevices()
            let updated = SourceCatalogue.sources(windows: windows, devices: devices)
            if updated != sources { sources = updated }
            lastError = nil
        } catch let error as MirrorError {
            // An empty list plus a reason, rather than an empty list that looks
            // like "nothing is running".
            lastError = error
            sources = [
                MirrorSourceDescriptor(
                    id: SourceCatalogue.windowPickerIdentifier, name: "Choose Window…",
                    kind: .window)
            ]
        } catch {
            lastError = .captureFailed(reason: error.localizedDescription)
        }
    }

    public func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                // Breaks the loop once the owner is gone. `await self?.refresh()`
                // alone would keep polling forever against a nil, which is a
                // spin rather than a stop. `deinit` cannot cancel this: it is
                // nonisolated and `monitor` is main-actor bound.
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    public func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    /// Builds a connectable source from a pickable one.
    ///
    /// Lives here rather than in the view so the mapping from descriptor to
    /// backend is stated once. A descriptor whose source has gone away since the
    /// list was drawn reports `sourceDisappeared` rather than returning
    /// something that cannot start.
    public func makeSource(for descriptor: MirrorSourceDescriptor) async throws -> any MirrorSource {
        switch descriptor.kind {
        case .window:
            return WindowSource()

        case .simulator:
            let sources = try await SimulatorSource.availableSources()
            guard
                let match = sources.first(where: {
                    SourceCatalogue.identifier(forSimulatorNamed: $0.displayName) == descriptor.id
                })
            else { throw MirrorError.sourceDisappeared(id: descriptor.id) }
            return match

        case .device:
            let sources = try await DeviceSource.availableSources()
            guard let match = sources.first(where: { $0.id == descriptor.id }) else {
                throw MirrorError.sourceDisappeared(id: descriptor.id)
            }
            return match
        }
    }
}
