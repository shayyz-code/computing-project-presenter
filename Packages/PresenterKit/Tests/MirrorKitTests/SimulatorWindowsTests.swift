import Foundation
import ScreenCaptureKit
import Testing

@testable import MirrorKit

private func window(
    id: CGWindowID = 1, title: String? = "iPhone 17 – iOS 26.4",
    bundle: String? = SimulatorWindows.bundleIdentifier,
    width: Int = 430, height: Int = 932
) -> CapturableWindow {
    CapturableWindow(id: id, title: title, bundleIdentifier: bundle, width: width, height: height)
}

@Suite("SimulatorWindows")
struct SimulatorWindowsTests {

    @Test("Finds the Simulator's device window")
    func findsDevice() {
        let windows = [
            window(id: 1),
            window(id: 2, title: "Xcode", bundle: "com.apple.dt.Xcode", width: 1600, height: 1000),
            window(id: 3, title: "Safari", bundle: "com.apple.Safari", width: 1200, height: 800),
        ]
        let found = SimulatorWindows.devices(in: windows)
        #expect(found.map(\.id) == [1])
    }

    @Test("The documented SimulatorTrampoline identifier matches nothing")
    func trampolineIdentifierIsWrong() {
        // spec 0002 and issue #23 both named this. It is the XPC service that
        // *launches* the Simulator and owns no windows, so filtering on it
        // yields an empty list — which presents as "capture is broken" rather
        // than "wrong identifier", and is why this test exists rather than a
        // comment.
        let windows = [window(id: 1, bundle: "com.apple.CoreSimulator.SimulatorTrampoline")]
        #expect(SimulatorWindows.devices(in: windows).isEmpty)

        // The identifier that does work.
        #expect(SimulatorWindows.bundleIdentifier == "com.apple.iphonesimulator")
    }

    @Test("Ignores the Simulator's own chrome windows")
    func ignoresChrome() {
        // The Simulator owns helper windows besides the device. Capturing one
        // gives a blank pane that looks exactly like a capture failure.
        let windows = [
            window(id: 1, title: "", width: 100, height: 30),
            window(id: 2, title: nil, width: 400, height: 900),
            window(id: 3, title: "iPhone 17 – iOS 26.4", width: 0, height: 0),
            window(id: 4, title: "iPhone 17 – iOS 26.4", width: 430, height: 932),
        ]
        #expect(SimulatorWindows.devices(in: windows).map(\.id) == [4])
    }

    @Test("Several booted simulators come back largest first")
    func ordersBySize() {
        let windows = [
            window(id: 1, title: "iPhone SE", width: 375, height: 667),
            window(id: 2, title: "iPad Pro", width: 1024, height: 1366),
            window(id: 3, title: "iPhone 17", width: 430, height: 932),
        ]
        #expect(SimulatorWindows.devices(in: windows).map(\.id) == [2, 3, 1])
    }

    @Test("No Simulator running is an empty list, not a failure")
    func noSimulator() {
        // Booting one later must just start working, so absence cannot be an
        // error state.
        let windows = [window(id: 1, title: "Safari", bundle: "com.apple.Safari")]
        #expect(SimulatorWindows.devices(in: windows).isEmpty)
    }

    @Test("Display name comes from the window title")
    func displayName() {
        // SCWindow has no device concept; the title is the only place the device
        // identity appears.
        #expect(SimulatorWindows.displayName(for: window()) == "iPhone 17 – iOS 26.4")
        #expect(SimulatorWindows.displayName(for: window(title: "   ")) == "Simulator")
        #expect(SimulatorWindows.displayName(for: window(title: nil)) == "Simulator")
    }
}

@MainActor
@Suite("Frame watchdog")
struct FrameWatchdogTests {

    @Test("The timeout is short enough that black is never the resting state")
    func timeoutIsShort() {
        // A stream that starts cleanly and delivers nothing is indistinguishable
        // from success at the API level, so the only detection is elapsed time
        // with no frame. Too long and the user stares at black wondering; this
        // bounds it.
        #expect(SimulatorSource.firstFrameTimeout <= .seconds(5))
        #expect(SimulatorSource.firstFrameTimeout >= .seconds(1))
    }

    @Test("A no-frames failure is captureFailed and says what to check")
    func noFramesMessage() {
        // The message has to name the causes, because "no frames" alone gives
        // the user nothing to act on. Hidden, minimised and Space are the three
        // ways a window exists but is not drawn.
        let error = MirrorError.captureFailed(
            reason: "Capture started but no frames arrived. The Simulator may be hidden, "
                + "minimised, or on another Space.")
        guard case .captureFailed(let reason) = error else {
            Issue.record("expected captureFailed")
            return
        }
        #expect(reason.contains("hidden"))
        #expect(reason.contains("Space"))
    }
}

@Suite("MirrorError mapping")
struct MirrorErrorMappingTests {

    private func scError(_ code: Int) -> NSError {
        NSError(
            domain: SCStreamErrorDomain, code: code,
            userInfo: [
                NSLocalizedDescriptionKey: "stream error \(code)"
            ])
    }

    @Test("Declined consent maps to permissionDenied", arguments: [-3801, -3803])
    func permissionDenied(code: Int) {
        // UserDeclined and MissingEntitlements. These are the only cases where
        // sending the user to System Settings helps, so they must not be lumped
        // in with captureFailed.
        #expect(MirrorError.from(scError(code), kind: .simulator) == .permissionDenied(.simulator))
    }

    @Test("A vanished source maps to sourceDisappeared", arguments: [-3815, -3817, -3821])
    func sourceDisappeared(code: Int) {
        // NoCaptureSource, UserStopped, SystemStoppedStream. The pane must show
        // a reconnect state, not a frozen last frame — a frozen frame is worse
        // than an error because the presenter keeps talking to a dead image.
        guard case .sourceDisappeared = MirrorError.from(scError(code), kind: .simulator) else {
            Issue.record("code \(code) should be sourceDisappeared")
            return
        }
    }

    @Test("Other stream errors map to captureFailed carrying the reason")
    func captureFailed() {
        guard case .captureFailed(let reason) = MirrorError.from(scError(-3802), kind: .simulator)
        else {
            Issue.record("expected captureFailed")
            return
        }
        #expect(reason.contains("-3802"))
    }

    @Test("A non-ScreenCaptureKit error is not mistaken for a denial")
    func foreignDomain() {
        // A file-system or network error must never send the user to the Screen
        // Recording pane, which is what a naive code check would do: -3801 is a
        // perfectly ordinary code in other domains.
        let error = NSError(
            domain: NSPOSIXErrorDomain, code: -3801,
            userInfo: [
                NSLocalizedDescriptionKey: "unrelated"
            ])
        guard case .captureFailed = MirrorError.from(error, kind: .simulator) else {
            Issue.record("a foreign domain must not map to permissionDenied")
            return
        }
    }

    @Test("The denial carries the kind, so the UI opens the right Settings pane")
    func deniedCarriesKind() {
        // Screen Recording and Camera are different panes. Getting this wrong
        // sends the user somewhere that cannot fix their problem.
        #expect(MirrorError.from(scError(-3801), kind: .window) == .permissionDenied(.window))
        #expect(MirrorSourceKind.simulator.needsScreenRecordingPermission)
    }
}
