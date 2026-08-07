import Foundation
import Testing

@testable import MirrorKit

/// The three devices a connected iPhone actually publishes, as measured in
/// spike #22 against an iPhone 13 Pro Max. Reproduced exactly, because the
/// values are counter-intuitive and paraphrasing them would lose the point.
private enum RealDevices {
    /// The one we want. Note `modelID` is the literal string "iOS Device".
    static let screen = CapturableDevice(
        uniqueID: "38DA121C-00B4-48E9-9464-BBED0B7EB623",
        localizedName: "Shayy", modelID: "iOS Device",
        isMuxed: true, isContinuityCamera: false, isDeskViewCamera: false, formatCount: 1)

    /// The decoy. Carries the iPhone model identifier and eight healthy formats.
    static let continuityCamera = CapturableDevice(
        uniqueID: "B6EC0710-4D58-4C7B-804C-38C700000001",
        localizedName: "Shayy Camera", modelID: "iPhone14,3",
        isMuxed: false, isContinuityCamera: true, isDeskViewCamera: false, formatCount: 8)

    static let deskView = CapturableDevice(
        uniqueID: "B6EC0710-4D58-4C7B-804C-38C700000002",
        localizedName: "Shayy Desk View Camera", modelID: "iPhone14,3",
        isMuxed: false, isContinuityCamera: false, isDeskViewCamera: true, formatCount: 1)

    static let builtInWebcam = CapturableDevice(
        uniqueID: "1FD4B3A2-236E-492B-8CE5-255DD288CE50",
        localizedName: "FaceTime HD Camera", modelID: "FaceTime HD Camera",
        isMuxed: false, isContinuityCamera: false, isDeskViewCamera: false, formatCount: 7)

    static let virtualCamera = CapturableDevice(
        uniqueID: "7626645E-4425-469E-9D8B-97E0FA59AC75",
        localizedName: "OBS Virtual Camera", modelID: "OBS Camera Extension",
        isMuxed: false, isContinuityCamera: false, isDeskViewCamera: false, formatCount: 1)

    static let all = [screen, continuityCamera, deskView, builtInWebcam, virtualCamera]
}

@Suite("DeviceDiscovery")
struct DeviceDiscoveryTests {

    @Test("Picks the screen out of everything a connected iPhone publishes")
    func picksTheScreen() {
        let found = DeviceDiscovery.screens(in: RealDevices.all)
        #expect(found.map(\.uniqueID) == [RealDevices.screen.uniqueID])
    }

    @Test("Rejects the Continuity camera — selecting it would mirror the room")
    func rejectsContinuity() {
        // The failure this whole type exists to prevent. It is silent: the
        // Continuity camera produces a perfectly good live image, just of the
        // wrong thing, and nobody notices until the deck is a picture of the
        // audience.
        #expect(DeviceDiscovery.screens(in: [RealDevices.continuityCamera]).isEmpty)
        #expect(DeviceDiscovery.screens(in: [RealDevices.deskView]).isEmpty)
    }

    @Test("modelID prefix matching would select exactly the wrong device")
    func modelIDIsInverted() {
        // Guards against someone "simplifying" the filter later. The screen's
        // modelID is "iOS Device"; it is the DECOYS that carry "iPhone14,3", so
        // the obvious heuristic is precisely backwards.
        let byModelPrefix = RealDevices.all.filter { $0.modelID.hasPrefix("iPhone") }
        #expect(byModelPrefix.allSatisfy { $0.isContinuityCamera || $0.isDeskViewCamera })
        #expect(!byModelPrefix.contains { $0.uniqueID == RealDevices.screen.uniqueID })

        // And a name prefix matches all three, so it discriminates nothing.
        let byNamePrefix = RealDevices.all.filter { $0.localizedName.hasPrefix("Shayy") }
        #expect(byNamePrefix.count == 3)
    }

    @Test("A device with no formats is a name in a list, not a source")
    func rejectsFormatless() {
        let formatless = CapturableDevice(
            uniqueID: "x", localizedName: "Ghost", modelID: "iOS Device",
            isMuxed: true, isContinuityCamera: false, isDeskViewCamera: false, formatCount: 0)
        #expect(DeviceDiscovery.screens(in: [formatless]).isEmpty)
    }

    @Test("No device attached is an empty list, not a failure")
    func noDevice() {
        // Plugging one in later must just start working, so absence cannot be
        // an error state.
        #expect(DeviceDiscovery.screens(in: [RealDevices.builtInWebcam, RealDevices.virtualCamera]).isEmpty)
        #expect(DeviceDiscovery.screens(in: []).isEmpty)
    }

    @Test("Two phones both appear")
    func twoDevices() {
        let second = CapturableDevice(
            uniqueID: "second", localizedName: "Other Phone", modelID: "iOS Device",
            isMuxed: true, isContinuityCamera: false, isDeskViewCamera: false, formatCount: 1)
        #expect(DeviceDiscovery.screens(in: RealDevices.all + [second]).count == 2)
    }

    @Test("The publication wait is long enough for a measured cold start")
    func publicationTimeout() {
        // Publication took 0.6–2.3s after setting the property, and is
        // intermittent for several seconds after a previous session releases the
        // device. A short timeout turns that into a spurious "no device".
        #expect(DeviceDiscovery.publicationTimeout >= .seconds(5))
    }

    @Test("Device capture needs Camera consent, not Screen Recording")
    func permissionKind() {
        // Different TCC services and different Settings panes. Sending someone
        // to the wrong one wastes their time mid-presentation.
        #expect(!MirrorSourceKind.device.needsScreenRecordingPermission)
        #expect(MirrorSourceKind.simulator.needsScreenRecordingPermission)
    }
}

@Suite("DeviceChassis")
struct DeviceChassisTests {
    private let pane = CGRect(x: 0, y: 0, width: 800, height: 600)
    /// The measured device: 1284x2778, i.e. tall and narrow.
    private let phoneAspect: CGFloat = 1284.0 / 2778.0

    @Test("The whole chassis fits inside the pane")
    func chassisFits() {
        // The chassis is what gets fitted, not the screen -- otherwise the
        // device's own edges get cropped off by the pane.
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: pane)
        #expect(chassis.width <= pane.width + 0.01)
        #expect(chassis.height <= pane.height + 0.01)
        #expect(abs(chassis.midX - pane.midX) < 0.01)
        #expect(abs(chassis.midY - pane.midY) < 0.01)
    }

    @Test("The screen sits inside the chassis on every side")
    func screenIsInset() {
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: pane)
        let screen = DeviceChassis.screenRect(inChassis: chassis)
        #expect(screen.minX > chassis.minX)
        #expect(screen.maxX < chassis.maxX)
        #expect(screen.minY > chassis.minY)
        #expect(screen.maxY < chassis.maxY)
    }

    @Test("Corners are concentric, so the bezel reads as even")
    func concentricCorners() {
        // Inner radius = outer minus bezel. Equal radii make the corners look
        // subtly wrong in a way that is hard to name but easy to see.
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: pane)
        let outer = DeviceChassis.cornerRadius(forChassis: chassis)
        let inner = DeviceChassis.screenCornerRadius(forChassis: chassis)
        #expect(inner < outer)
        #expect(inner >= 0)
    }

    @Test("Side buttons sit outside the body, on the side they belong to")
    func buttonsAreOutside() {
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: pane)
        let rects = DeviceChassis.buttonRects(forChassis: chassis)
        #expect(rects.count == DeviceChassis.sideButtons.count)

        for (button, rect) in zip(DeviceChassis.sideButtons, rects) {
            // Proud of the body, not overlapping it -- a button drawn inside the
            // bezel reads as a scratch on the screen.
            switch button.edge {
            case .left: #expect(rect.maxX <= chassis.minX + 0.01)
            case .right: #expect(rect.minX >= chassis.maxX - 0.01)
            }
            #expect(rect.minY >= chassis.minY)
            #expect(rect.maxY <= chassis.maxY)
        }
    }

    @Test("Buttons are ordered from the top of the phone, not the bottom")
    func buttonsRunFromTheTop() {
        // The one that inverts silently. `start` is a distance from the top, but
        // the host view is unflipped, so the arithmetic runs down from maxY.
        // Get it backwards and the volume keys move next to the speaker, which
        // looks plausible enough in a small pane to survive review.
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: pane)
        let rects = DeviceChassis.buttonRects(forChassis: chassis)

        // The action button is declared first and sits highest on the phone, so
        // in unflipped space it has the largest maxY of the three on the left.
        let left = zip(DeviceChassis.sideButtons, rects).filter { $0.0.edge == .left }.map(\.1)
        #expect(left.count == 3)
        #expect(left[0].maxY > left[1].maxY)
        #expect(left[1].maxY > left[2].maxY)

        // And all of them sit in the top half, as they do on a real phone.
        #expect(left.allSatisfy { $0.midY > chassis.midY })
    }

    @Test("The rim never eats more than the bezel it is drawn inside")
    func rimFitsInsideBezel() {
        // Both are drawn from the body edge inward. A rim wider than the bezel
        // would overlap the screen.
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: pane)
        let bezel = min(chassis.width, chassis.height) * DeviceChassis.bezelRatio
        #expect(DeviceChassis.rimWidth(forChassis: chassis) <= bezel)
        #expect(DeviceChassis.rimWidth(forChassis: chassis) > 0)
    }

    @Test("Degenerate input yields an empty rect rather than NaN geometry")
    func degenerate() {
        #expect(DeviceChassis.chassisRect(screenAspect: 0, in: pane) == .zero)
        #expect(DeviceChassis.chassisRect(screenAspect: .nan, in: pane) == .zero)
        #expect(DeviceChassis.buttonRects(forChassis: .zero).isEmpty)
        // A pane can be laid out at zero size for a frame during a resize.
        #expect(DeviceChassis.chassisRect(screenAspect: phoneAspect, in: .zero) == .zero)
        #expect(DeviceChassis.screenRect(inChassis: .zero) == .zero)
    }

    @Test("Scales with the pane rather than being fixed", arguments: [200.0, 800.0, 2400.0])
    func scalesWithPane(width: CGFloat) {
        // Proportional geometry: the device looks the same at any size, which is
        // what lets one implementation serve a small pane and a projector.
        let bounds = CGRect(x: 0, y: 0, width: width, height: width * 1.5)
        let chassis = DeviceChassis.chassisRect(screenAspect: phoneAspect, in: bounds)
        let screen = DeviceChassis.screenRect(inChassis: chassis)
        let bezel = screen.minX - chassis.minX
        #expect(abs(bezel / min(chassis.width, chassis.height) - DeviceChassis.bezelRatio) < 0.001)
    }
}
