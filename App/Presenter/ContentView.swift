import PresenterCore
import SwiftUI

/// The presenting window's two-pane shape: deck on the left, live device on the
/// right. Both panes are placeholders — M1 fills the left, M2 the right.
struct ContentView: View {
    /// Empty until M1 loads a real deck. Present now so the app target's
    /// dependency on PresenterKit is exercised at build time rather than assumed.
    private let navigator = SlideNavigator(count: 0)

    var body: some View {
        HSplitView {
            PlaceholderPane(
                title: "Slides",
                detail: "Open a .pdf or .pptx deck  ·  \(navigator.position)/\(navigator.count)",
                symbol: "rectangle.on.rectangle"
            )
            PlaceholderPane(
                title: "Device",
                detail: "Mirror a simulator or a connected iPhone",
                symbol: "iphone.gen3"
            )
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}

private struct PlaceholderPane: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.background.secondary)
    }
}

#Preview {
    ContentView()
}
