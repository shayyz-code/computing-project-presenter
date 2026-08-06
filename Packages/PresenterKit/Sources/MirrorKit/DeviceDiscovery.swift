import AVFoundation
import CoreMediaIO
import Foundation

/// The part of an `AVCaptureDevice` that source selection cares about.
///
/// A value type so the selection rules below can be tested without a phone
/// plugged in, which CI does not have. `DeviceSource` maps real devices into
/// these, picks one, then finds the original by `uniqueID`.
public struct CapturableDevice: Equatable, Sendable {
    public let uniqueID: String
    public let localizedName: String
    public let modelID: String
    public let isMuxed: Bool
    public let isContinuityCamera: Bool
    public let isDeskViewCamera: Bool
    public let formatCount: Int

    public init(
        uniqueID: String, localizedName: String, modelID: String, isMuxed: Bool,
        isContinuityCamera: Bool, isDeskViewCamera: Bool, formatCount: Int
    ) {
        self.uniqueID = uniqueID
        self.localizedName = localizedName
        self.modelID = modelID
        self.isMuxed = isMuxed
        self.isContinuityCamera = isContinuityCamera
        self.isDeskViewCamera = isDeskViewCamera
        self.formatCount = formatCount
    }
}

/// Picking the iPhone's *screen* out of everything a connected phone publishes.
public enum DeviceDiscovery {

    /// Devices that are an iOS screen, in publication order.
    ///
    /// A connected iPhone publishes **three** capture devices, and the screen is
    /// the least obvious of them:
    ///
    /// | Device | localizedName | modelID | muxed | isContinuityCamera |
    /// |---|---|---|---|---|
    /// | screen — want | `Shayy` | `iOS Device` | yes | false |
    /// | Continuity | `Shayy Camera` | `iPhone14,3` | no | **true** |
    /// | Desk View | `Shayy Desk View Camera` | `iPhone14,3` | no | false |
    ///
    /// Measured in spike #22. Note `modelID` is **inverted** from the obvious
    /// guess: the screen reports the literal string `iOS Device` while the
    /// *decoys* carry `iPhone14,3`. So `modelID.hasPrefix("iPhone")` selects the
    /// phone's rear lens and mirrors the room — a failure that looks entirely
    /// plausible until someone notices the slide deck is a picture of the
    /// audience. Name prefixes match all three, and all three report
    /// `deviceType == .external`, so neither discriminates either.
    ///
    /// The media type is what separates them.
    public static func screens(in devices: [CapturableDevice]) -> [CapturableDevice] {
        devices.filter { device in
            device.isMuxed
                && !device.isContinuityCamera
                && !device.isDeskViewCamera
                // A device with no formats is a name in a list, not a source.
                && device.formatCount > 0
        }
    }

    /// Enables CoreMediaIO's screen-capture devices.
    ///
    /// Without this the iPhone's screen is never published at all. Returns the
    /// `OSStatus` so a failure is visible rather than assumed — it has returned
    /// `noErr` on every macOS tested, but silently assuming that is how this
    /// codebase got into trouble before.
    @discardableResult
    public static func allowScreenCaptureDevices() -> OSStatus {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        return CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &allow)
    }

    /// How long to wait for the device to be published.
    ///
    /// Publication is asynchronous — measured at 0.6–2.3 s after the property is
    /// set — so a one-shot enumeration is a race that *sometimes wins*, which is
    /// worse than always failing because it looks like flakiness rather than a
    /// bug. It is also intermittent for a few seconds after a previous capture
    /// session releases the device: 2 of 3 back-to-back attempts succeeded,
    /// 3 of 3 with an 8 s gap. So absence is transient, never a verdict.
    public static let publicationTimeout: Duration = .seconds(8)

    /// The device types worth searching. `.external` is where a DAL-published
    /// iOS screen lands; the Continuity types are included so they can be
    /// explicitly rejected rather than silently absent.
    public static let deviceTypes: [AVCaptureDevice.DeviceType] = [
        .external, .continuityCamera, .deskViewCamera,
    ]
}

extension CapturableDevice {
    /// Snapshot of a live `AVCaptureDevice`.
    public init(_ device: AVCaptureDevice) {
        self.init(
            uniqueID: device.uniqueID,
            localizedName: device.localizedName,
            modelID: device.modelID,
            isMuxed: device.hasMediaType(.muxed),
            isContinuityCamera: device.isContinuityCamera,
            isDeskViewCamera: device.deviceType == .deskViewCamera,
            formatCount: device.formats.count)
    }
}
