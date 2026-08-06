import AppKit
import MirrorKit
import SwiftUI

/// The right pane: a live iOS screen.
///
/// Minimal on purpose — this slice proves capture works. Aspect-fit refinement,
/// rotation handling and the full permission UI are #26; source discovery with
/// live list updates is #24.
struct MirrorPane: View {
    @State private var source: SimulatorSource?
    @State private var state: MirrorState = .idle

    var body: some View {
        Group {
            switch state {
            case .idle:
                MirrorMessage(
                    symbol: "iphone.gen3", title: "Device", detail: "No source selected"
                ) {
                    Button("Mirror Simulator") { Task { await connect() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }

            case .searching:
                MirrorMessage(
                    symbol: "iphone.gen3", title: "Device", detail: "Looking for a Simulator…"
                ) {
                    ProgressView().controlSize(.small)
                }

            case .mirroring(let layer):
                // The layer travels in the case rather than beside it. Holding
                // it separately let `.mirroring` coexist with a nil layer, which
                // rendered as a bare spinner with no way out — and `onDisappear`
                // firing spuriously was enough to cause it.
                LayerHost(layer: layer)

            case .noSource:
                MirrorMessage(
                    symbol: "iphone.slash",
                    title: "No Simulator running",
                    detail: "Boot one from Xcode, then try again."
                ) {
                    Button("Try Again") { Task { await connect() } }
                        .buttonStyle(.glass)
                }

            case .denied:
                // Recoverable by the user, so it must say so and take them
                // there. A blank pane here is a bug, per spec 0002.
                MirrorMessage(
                    symbol: "lock.display",
                    title: "Screen Recording is off",
                    detail: "Presenter needs Screen Recording permission to mirror a Simulator."
                ) {
                    Button("Open Settings") { openScreenRecordingSettings() }
                        .buttonStyle(.glassProminent)
                }

            case .failed(let reason):
                MirrorMessage(
                    symbol: "exclamationmark.triangle",
                    title: "Could not mirror",
                    detail: reason
                ) {
                    Button("Try Again") { Task { await connect() } }
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
                    Button("Reconnect") { Task { await connect() } }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Deliberately no `.onDisappear` teardown. SwiftUI fires it for
        // transient reasons — a modal appearing was enough — and tearing the
        // stream down there stopped the mirror without telling anyone.
        // The pane lives as long as the window; the window closing releases it.
    }

    private func connect() async {
        await disconnect()
        state = .searching

        do {
            let sources = try await SimulatorSource.availableSources()
            guard let first = sources.first else {
                // Absence is normal, not a failure — booting one later works.
                state = .noSource
                return
            }
            first.onStopped = { _ in
                Task { @MainActor in
                    self.source = nil
                    state = .disconnected
                }
            }
            let layer = try await first.start()
            source = first
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

    private func openScreenRecordingSettings() {
        // Screen Recording, not Camera. They are different panes and sending
        // someone to the wrong one wastes their time at exactly the moment they
        // are trying to present.
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
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

    func makeNSView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.mirrored = layer
        return view
    }

    func updateNSView(_ view: LayerHostView, context: Context) {
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
    var mirrored: CALayer? {
        didSet {
            guard mirrored !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let mirrored { layer?.addSublayer(mirrored) }
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        guard let mirrored else { return }
        // Implicit animation would make every resize a visible slide of the
        // mirrored screen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrored.frame = bounds
        CATransaction.commit()
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
