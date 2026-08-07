import PresenterCore
import SlideKit
import SwiftUI

/// Speaker notes for the current slide, with the elapsed timer.
///
/// **Presenter-only.** Nothing in here may ever appear on an audience display —
/// notes and a running clock are exactly what the room must not see. Multi-
/// display is #31, so today that is a constraint rather than code; the pane is
/// kept a separate view so moving it to a presenter-only window is a
/// reparenting rather than a rewrite.
struct NotesPane: View {
    let deck: Deck?
    let slideNumber: Int
    let timer: PresentationTimer

    /// The notes for the current slide, resolved by the **author-facing**
    /// number rather than an array offset. That is the whole reason `Deck`
    /// keys slides by `number`: PPTX order comes from `<p:sldIdLst>`, and
    /// indexing would quietly show the wrong slide's notes.
    private var notes: String? {
        deck?[number: slideNumber]?.notes
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let notes {
                    ScrollView {
                        Text(notes)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else {
                    // A slide with no notes shows nothing — not a labelled empty
                    // box, which reads as "something failed to load" at a glance.
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TimerReadout(timer: timer)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

/// The elapsed clock plus its controls.
private struct TimerReadout: View {
    let timer: PresentationTimer
    /// Drives redraws. `PresentationTimer` computes elapsed on demand rather
    /// than ticking, so something has to ask it — once a second is enough for a
    /// seconds-resolution readout and costs nothing.
    @State private var tick = Date()
    private let heartbeat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            Text(timer.formatted)
                // Monospaced digits, or the clock jitters horizontally every
                // second and pulls the eye during a talk.
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())

            HStack(spacing: 8) {
                Button {
                    timer.isRunning ? timer.pause() : timer.resume()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.glass)
                .help(timer.isRunning ? "Pause the timer" : "Start the timer")

                Button {
                    timer.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .help("Reset the timer")
            }
        }
        .onReceive(heartbeat) { tick = $0 }
        // Reading `tick` is what ties the redraw to the heartbeat.
        .id(tick.timeIntervalSince1970.rounded())
    }
}
