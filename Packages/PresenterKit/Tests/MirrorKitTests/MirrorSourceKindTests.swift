import Testing

@testable import MirrorKit

@Suite("MirrorSourceKind")
struct MirrorSourceKindTests {
    @Test("Simulator and window capture need Screen Recording; device capture does not")
    func permissionMapping() {
        // The device path goes through AVFoundation, so it sits behind Camera
        // consent rather than Screen Recording. Getting this backwards would send
        // the user to the wrong System Settings pane.
        #expect(MirrorSourceKind.simulator.needsScreenRecordingPermission)
        #expect(MirrorSourceKind.window.needsScreenRecordingPermission)
        #expect(!MirrorSourceKind.device.needsScreenRecordingPermission)
    }

    @Test("Every kind has a stable raw value for persisting a selection")
    func rawValuesAreStable() {
        #expect(MirrorSourceKind.allCases.count == 3)
        #expect(MirrorSourceKind(rawValue: "simulator") == .simulator)
        #expect(MirrorSourceKind(rawValue: "device") == .device)
        #expect(MirrorSourceKind(rawValue: "window") == .window)
    }
}
