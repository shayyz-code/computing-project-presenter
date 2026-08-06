// Spike #22, fifth probe — cold start, but waiting properly this time.
//
// The previous cold probe polled with Thread.sleep, which services no RunLoop,
// so for 45 seconds the process could not receive a single CoreFoundation
// notification. Device arrival on this path is notification-driven, and the
// warm runs only got away with it because the device was already published
// before the first query. That is a probe defect, and this spike has already
// produced two false negatives from probe defects.
//
// Three changes: RunLoop-serviced waiting, one retained DiscoverySession for
// the whole wait rather than a fresh one per iteration, and an explicit
// wasConnectedNotification observer with timestamps.

import AVFoundation
import CoreMediaIO
import Foundation

var address = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var allow: UInt32 = 1
let setStatus = CMIOObjectSetPropertyData(
    CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
    UInt32(MemoryLayout<UInt32>.size), &allow)

let start = Date()
func stamp() -> String { String(format: "%6.2fs", Date().timeIntervalSince(start)) }

print("Spike #22 — cold start with RunLoop-serviced waiting")
print("property set -> OSStatus \(setStatus)")

func isScreen(_ d: AVCaptureDevice) -> Bool {
    !d.isContinuityCamera && d.deviceType != .deskViewCamera && d.hasMediaType(.muxed)
}

// Retained for the whole wait. Constructing a new session each iteration was
// throwing away whatever observation state it builds up.
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external, .continuityCamera, .deskViewCamera, .builtInWideAngleCamera],
    mediaType: nil,
    position: .unspecified
)

NotificationCenter.default.addObserver(
    forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil
) { note in
    guard let d = note.object as? AVCaptureDevice else { return }
    print("\(stamp())  wasConnected: \(d.localizedName)  muxed=\(d.hasMediaType(.muxed)) continuity=\(d.isContinuityCamera)")
}

print("\(stamp())  initial: \(discovery.devices.map(\.localizedName).joined(separator: ", "))")
print("waiting up to 45s, servicing the RunLoop...\n")

var found: AVCaptureDevice?
while Date().timeIntervalSince(start) < 45 {
    if let d = discovery.devices.first(where: isScreen) {
        found = d
        break
    }
    // The fix: this services CFRunLoop sources, Thread.sleep did not.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
}

guard let device = found else {
    print("\n\(stamp())  NOT FOUND after RunLoop-serviced waiting.")
    print("  Final device list: \(discovery.devices.map(\.localizedName).joined(separator: ", "))")
    print("  Cold start genuinely does not work from an unentitled binary.")
    exit(1)
}

print("\n\(stamp())  FOUND: \(device.localizedName) (\(device.modelID), \(device.formats.count) formats)")

final class Counter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var frames = 0
    var dims: CMVideoDimensions?
    func captureOutput(
        _ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection
    ) {
        frames += 1
        if dims == nil, let d = CMSampleBufferGetFormatDescription(sb) {
            dims = CMVideoFormatDescriptionGetDimensions(d)
        }
    }
}

let session = AVCaptureSession()
let counter = Counter()
do { session.addInput(try AVCaptureDeviceInput(device: device)) } catch {
    print("  FAIL opening input: \(error.localizedDescription)"); exit(1)
}
let output = AVCaptureVideoDataOutput()
output.setSampleBufferDelegate(counter, queue: DispatchQueue(label: "frames"))
session.addOutput(output)
session.startRunning()
RunLoop.current.run(until: Date().addingTimeInterval(3))
session.stopRunning()

let dims = counter.dims.map { "\($0.width)x\($0.height)" } ?? "?"
print("  frames: \(counter.frames) in 3s, \(dims)")
