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
    @State private var layer: CALayer?
    @State private var state: MirrorState = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .searching:
                MirrorMessage(
                    symbol: "iphone.gen3",
                    title: "Device",
                    detail: state == .searching ? "Looking for a Simulator…" : "No source selected"
                ) {
                    Button("Mirror Simulator") { Task { await connect() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }

            case .mirroring:
                if let layer {
                    LayerHost(layer: layer)
                } else {
                    ProgressView()
                }

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
        .onDisappear { Task { await disconnect() } }
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
                    self.layer = nil
                    self.source = nil
                    state = .disconnected
                }
            }
            layer = try await first.start()
            source = first
            state = .mirroring
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
        layer = nil
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

private enum MirrorState: Equatable {
    case idle
    case searching
    case mirroring
    case noSource
    case denied
    case failed(String)
    case disconnected
}

/// Hosts a `CALayer` from any `MirrorSource`. One view for every backend is the
/// point of ADR-0003's layer-vending protocol.
private struct LayerHost: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = view.layer else { return }
        if layer.superlayer !== host {
            host.sublayers?.forEach { $0.removeFromSuperlayer() }
            host.addSublayer(layer)
        }
        // Implicit animation would make every resize a visible slide of the
        // mirrored screen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = host.bounds
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
