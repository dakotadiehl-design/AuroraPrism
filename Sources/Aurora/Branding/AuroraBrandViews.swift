import SwiftUI

/// App-catalog brand mark for permanent toolbar chrome (UI-02A).
struct AuroraMarkView: View {
    var size: CGFloat = 18

    var body: some View {
        Image("AuroraMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel("Aurora")
    }
}

/// Full wordmark for welcome / empty / About — not permanent toolbar.
struct AuroraWordmarkView: View {
    var height: CGFloat = 22

    var body: some View {
        Image("AuroraWordmark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityLabel("Aurora")
    }
}
