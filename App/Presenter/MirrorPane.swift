import AppKit
import MirrorKit
import SwiftUI

/// The right pane: a live iOS screen.
///
/// Minimal on purpose — this slice proves capture works. Aspect-fit refinement,
/// rotation handling and the full permission UI are #26; source discovery with
/// live list updates is #24.
struct MirrorPane: View {
    /// A source id remembered from the last session, pre-selected but never
    /// auto-connected — connecting would unhide a Simulator uninvited.
    let rememberedSourceID: String?
    let onSourceChanged: (String?) -> Void

    @State private var source: (any MirrorSource)?
    @State private var state: MirrorState = .idle
    @State private var discovery = SourceDiscovery()
    /// Which source was last attempted, so retries and permission messages
    /// address the right one.
    @State private var lastKind: MirrorSourceKind = .simulator
    @State private var lastDescriptor: MirrorSourceDescriptor?

    var body: some View {
        Group {
            switch state {
            case .idle:
                MirrorMessage(
                    symbol: "iphone.gen3", title: "Device",
                    detail: discovery.sources.count > 1
                        ? "Pick something to mirror" : "No Simulator or device found"
                ) {
                    SourcePicker(
                        sources: discovery.sources,
                        remembered: rememberedSourceID,
                        onSelect: { descriptor in Task { await connect(descriptor) } })
                }

            case .searching:
                MirrorMessage(
                    symbol: "iphone.gen3", title: "Device",
                    detail: lastKind == .device
                        ? "Looking for a connected iPhone…" : "Looking for a Simulator…"
                ) {
                    ProgressView().controlSize(.small)
                }

            case .mirroring(let layer):
                // The chassis is drawn only for a physical device. A Simulator
                // window already contains its own bezel, so framing it again
                // would put a phone inside a phone.
                // The layer travels in the case rather than beside it. Holding
                // it separately let `.mirroring` coexist with a nil layer, which
                // rendered as a bare spinner with no way out — and `onDisappear`
                // firing spuriously was enough to cause it.
                LayerHost(layer: layer, drawsChassis: lastKind == .device)

            case .noSource:
                MirrorMessage(
                    symbol: "iphone.slash",
                    title: lastKind == .device ? "No iPhone found" : "No Simulator running",
                    detail: lastKind == .device
                        ? "Connect an iPhone by USB, unlock it, and tap Trust."
                        : "Boot one from Xcode, then try again."
                ) {
                    Button("Try Again") { Task { await retry() } }
                        .buttonStyle(.glass)
                }

            case .denied:
                // Recoverable by the user, so it must say so and take them
                // there. A blank pane here is a bug, per spec 0002. Which pane
                // depends on the source: Screen Recording and Camera are
                // different TCC services, and the wrong link cannot help.
                MirrorMessage(
                    symbol: "lock.display",
                    title: lastKind.needsScreenRecordingPermission
                        ? "Screen Recording is off" : "Camera access is off",
                    detail: lastKind.needsScreenRecordingPermission
                        ? "Presenter needs Screen Recording permission to mirror a Simulator."
                        : "Presenter needs Camera permission to mirror a connected iPhone."
                ) {
                    Button("Open Settings") { openPrivacySettings(for: lastKind) }
                        .buttonStyle(.glassProminent)
                }

            case .failed(let reason):
                MirrorMessage(
                    symbol: "exclamationmark.triangle",
                    title: "Could not mirror",
                    detail: reason
                ) {
                    Button("Try Again") { Task { await retry() } }
                        .buttonStyle(.glass)
                }

            case .disconnected:
                // Never a frozen last frame: the presenter would keep talking to
                // a dead image with nothing telling them it had stopped.
                MirrorMessage(
                    symbol: "arrow.clockwise",
                    title: "Simulator disconnected",
                    detail: "The Simulator stopped or quit."
                ) {
                    Button("Reconnect") { Task { await retry() } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { discovery.startMonitoring() }
        // Deliberately no `.onDisappear` teardown. SwiftUI fires it for
        // transient reasons — a modal appearing was enough — and tearing the
        // stream down there stopped the mirror without telling anyone.
        // The pane lives as long as the window; the window closing releases it.
    }

    private func retry() async {
        if let lastDescriptor {
            await connect(lastDescriptor)
        } else {
            state = .idle
        }
    }

    private func connect(_ descriptor: MirrorSourceDescriptor) async {
        await disconnect()
        lastKind = descriptor.kind
        lastDescriptor = descriptor
        state = .searching

        do {
            let first = try await discovery.makeSource(for: descriptor)
            let onStopped: (MirrorError) -> Void = { _ in
                Task { @MainActor in
                    self.source = nil
                    state = .disconnected
                }
            }
            (first as? SimulatorSource)?.onStopped = onStopped
            (first as? DeviceSource)?.onStopped = onStopped
            let layer = try await first.start()
            source = first
            onSourceChanged(descriptor.id)
            state = .mirroring(layer)
        } catch let error as MirrorError {
            switch error {
            case .permissionDenied: state = .denied
            case .sourceDisappeared: state = .noSource
            case .captureFailed(let reason): state = .failed(reason)
            case .unsupportedOnThisSystem(let reason): state = .failed(reason)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func disconnect() async {
        await source?.stop()
        source = nil
    }

    private func openPrivacySettings(for kind: MirrorSourceKind) {
        // Screen Recording and Camera are different panes. Sending someone to
        // the wrong one wastes their time at exactly the moment they are trying
        // to present.
        let anchor =
            kind.needsScreenRecordingPermission ? "Privacy_ScreenCapture" : "Privacy_Camera"
        guard
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Not `Equatable`: `.mirroring` carries a `CALayer`, and identity comparison
/// of layers is not what any caller wants.
private enum MirrorState {
    case idle
    case searching
    case mirroring(CALayer)
    case noSource
    case denied
    case failed(String)
    case disconnected
}

/// Hosts a `CALayer` from any `MirrorSource`. One view for every backend is the
/// point of ADR-0003's layer-vending protocol.
private struct LayerHost: NSViewRepresentable {
    let layer: CALayer
    let drawsChassis: Bool

    func makeNSView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.drawsChassis = drawsChassis
        view.mirrored = layer
        return view
    }

    func updateNSView(_ view: LayerHostView, context: Context) {
        view.drawsChassis = drawsChassis
        view.mirrored = layer
    }
}

/// Hosts the mirrored layer and keeps it the size of the view.
///
/// Sizing has to happen in `layout()`, not in `updateNSView`. SwiftUI runs
/// `updateNSView` before AppKit has laid the view out, so the bounds are still
/// zero — the layer gets a 0x0 frame, and the pane shows solid black with no
/// hint that frames are arriving perfectly well.
final class LayerHostView: NSView {
    /// Whether to draw a device body around the feed. True for a physical
    /// device, whose feed is the bare screen; false for a Simulator, whose
    /// window already includes its chassis.
    var drawsChassis = false { didSet { needsLayout = true } }

    /// Aspect of the incoming video, discovered from the layer once frames flow.
    /// Falls back to a modern phone until then, so the first layout is close
    /// rather than square.
    var screenAspect: CGFloat = 1284.0 / 2778.0

    private let chassis = CALayer()

    var mirrored: CALayer? {
        didSet {
            guard mirrored !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let mirrored { chassis.addSublayer(mirrored) }
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        // Neutral rather than black: the mirror should read as a device resting
        // on a surface, not as a hole in the window.
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        chassis.backgroundColor = NSColor.black.cgColor
        chassis.masksToBounds = true
        layer?.addSublayer(chassis)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        guard let mirrored else { return }

        // Implicit animation would make every resize a visible slide of the
        // mirrored screen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard drawsChassis else {
            // Simulator: the captured window is the device, bezel included.
            chassis.frame = bounds
            chassis.cornerRadius = 0
            chassis.backgroundColor = NSColor.clear.cgColor
            mirrored.frame = chassis.bounds
            mirrored.cornerRadius = 0
            return
        }

        let body = DeviceChassis.chassisRect(screenAspect: screenAspect, in: bounds)
        chassis.backgroundColor = NSColor.black.cgColor
        chassis.frame = body
        chassis.cornerRadius = DeviceChassis.cornerRadius(forChassis: body)

        // screenRect is in the view's space; the mirrored layer is a child of
        // the chassis, so it is offset into the chassis's own coordinates.
        let screen = DeviceChassis.screenRect(inChassis: body)
        mirrored.frame = CGRect(
            x: screen.minX - body.minX, y: screen.minY - body.minY,
            width: screen.width, height: screen.height)
        mirrored.cornerRadius = DeviceChassis.screenCornerRadius(forChassis: body)
        mirrored.masksToBounds = true
    }
}

/// Lists everything discovery found, with the remembered source marked.
private struct SourcePicker: View {
    let sources: [MirrorSourceDescriptor]
    let remembered: String?
    let onSelect: (MirrorSourceDescriptor) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(sources) { descriptor in
                Button {
                    onSelect(descriptor)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: symbol(for: descriptor.kind))
                        Text(descriptor.name)
                        // Marks the source restored from the last session. It is
                        // pre-selected rather than connected, because connecting
                        // on launch would unhide a Simulator uninvited.
                        if descriptor.id == remembered {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .help("Used last time")
                        }
                    }
                }
                // Two branches rather than a type-erased style: SwiftUI has no
                // AnyButtonStyle, and erasing one by hand for a cosmetic
                // difference would cost more than it saves.
                .buttonStyle(.glass)
                .tint(descriptor.id == remembered ? Color.accentColor : nil)
            }
        }
    }

    private func symbol(for kind: MirrorSourceKind) -> String {
        switch kind {
        case .simulator: "iphone.gen3"
        case .device: "iphone"
        case .window: "macwindow"
        }
    }
}

private struct MirrorMessage<Action: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                action
                    .padding(.top, 6)
            }
            .padding(28)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
