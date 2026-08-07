import CoreGraphics
import Foundation
import Testing

@testable import MirrorKit

private func simWindow(id: CGWindowID, title: String) -> CapturableWindow {
    CapturableWindow(
        id: id, title: title, bundleIdentifier: SimulatorWindows.bundleIdentifier,
        width: 430, height: 932)
}

private func phone(uniqueID: String, name: String) -> CapturableDevice {
    CapturableDevice(
        uniqueID: uniqueID, localizedName: name, modelID: "iOS Device", isMuxed: true,
        isContinuityCamera: false, isDeskViewCamera: false, formatCount: 1)
}

private let continuityDecoy = CapturableDevice(
    uniqueID: "decoy", localizedName: "Shayy Camera", modelID: "iPhone14,3", isMuxed: false,
    isContinuityCamera: true, isDeskViewCamera: false, formatCount: 8)

@Suite("SourceCatalogue")
struct SourceCatalogueTests {

    @Test("Lists simulators, then devices, then the window picker")
    func ordering() {
        // Ordered deliberately: the Simulator is the common case in
        // development, and choosing an arbitrary window is a deliberate act, so
        // it belongs last.
        let sources = SourceCatalogue.sources(
            windows: [simWindow(id: 1, title: "iPhone 17")],
            devices: [phone(uniqueID: "abc", name: "Shayy")])

        #expect(sources.map(\.kind) == [.simulator, .device, .window])
        #expect(sources.map(\.name) == ["iPhone 17", "Shayy", "Choose Window…"])
    }

    @Test("A Simulator's identity survives its window id changing")
    func simulatorIdentityIsStable() {
        // The criterion this design exists for. Quit a Simulator and relaunch
        // it and CGWindowID changes — so an id built from it would silently
        // stop matching the selection session restore remembered.
        let before = SourceCatalogue.sources(
            windows: [simWindow(id: 505, title: "iPhone 17")], devices: [])
        let after = SourceCatalogue.sources(
            windows: [simWindow(id: 9182, title: "iPhone 17")], devices: [])

        #expect(before.first?.id == after.first?.id)
        #expect(before.first?.id == "simulator-iPhone 17")
    }

    @Test("A device's identity is its uniqueID")
    func deviceIdentity() {
        let sources = SourceCatalogue.sources(
            windows: [], devices: [phone(uniqueID: "38DA121C", name: "Shayy")])
        #expect(sources.first?.id == "device-38DA121C")
    }

    @Test("Continuity decoys never appear as sources")
    func rejectsDecoys() {
        // Selecting one would mirror the room. The filtering lives in
        // DeviceDiscovery; this asserts the catalogue actually applies it.
        let sources = SourceCatalogue.sources(windows: [], devices: [continuityDecoy])
        #expect(sources.map(\.kind) == [.window], "only the picker should remain")
    }

    @Test("An empty environment still offers the window picker")
    func emptyEnvironment() {
        // Not an error state: no Simulator and no phone is normal, and choosing
        // a window must still be possible.
        let sources = SourceCatalogue.sources(windows: [], devices: [])
        #expect(sources.count == 1)
        #expect(sources.first?.id == SourceCatalogue.windowPickerIdentifier)
    }

    @Test("One simulator with several windows appears once")
    func deduplicates() {
        // The Simulator owns more than the device window; two entries for the
        // same phone would be confusing to pick between.
        let sources = SourceCatalogue.sources(
            windows: [simWindow(id: 1, title: "iPhone 17"), simWindow(id: 2, title: "iPhone 17")],
            devices: [])
        #expect(sources.filter { $0.kind == .simulator }.count == 1)
    }

    @Test("Several simulators each appear")
    func multipleSimulators() {
        let sources = SourceCatalogue.sources(
            windows: [simWindow(id: 1, title: "iPhone 17"), simWindow(id: 2, title: "iPad Pro")],
            devices: [])
        #expect(sources.filter { $0.kind == .simulator }.map(\.name).sorted() == ["iPad Pro", "iPhone 17"])
    }

    @Test("Diffing reports what appeared and what went away")
    func diffing() {
        let before = SourceCatalogue.sources(
            windows: [simWindow(id: 1, title: "iPhone 17")], devices: [])
        let after = SourceCatalogue.sources(
            windows: [], devices: [phone(uniqueID: "abc", name: "Shayy")])

        let changes = SourceCatalogue.changes(from: before, to: after)
        #expect(changes.appeared.map(\.name) == ["Shayy"])
        #expect(changes.disappeared.map(\.name) == ["iPhone 17"])
    }

    @Test("An unchanged list reports no changes")
    func noChanges() {
        // Refreshes happen every two seconds; a steady environment must not
        // look like constant churn.
        let list = SourceCatalogue.sources(
            windows: [simWindow(id: 1, title: "iPhone 17")], devices: [])
        let changes = SourceCatalogue.changes(from: list, to: list)
        #expect(changes.appeared.isEmpty)
        #expect(changes.disappeared.isEmpty)
    }

    @Test("A remembered selection is recognised while it is present")
    func remembersSelection() {
        // Session restore stores this id, so it has to match what the catalogue
        // produces on the next launch.
        let sources = SourceCatalogue.sources(
            windows: [simWindow(id: 1, title: "iPhone 17")], devices: [])

        #expect(SourceCatalogue.contains("simulator-iPhone 17", in: sources))
        #expect(!SourceCatalogue.contains("simulator-iPad Pro", in: sources))
        #expect(!SourceCatalogue.contains(nil, in: sources))
    }

    @MainActor
    @Test("Polling is frequent enough for the spec's ~2s")
    func refreshInterval() {
        // There is nothing to observe — SCShareableContent publishes no change
        // notification — so the interval is what meets "appears within ~2s of
        // booting".
        #expect(SourceDiscovery.refreshInterval <= .seconds(2))
    }
}
