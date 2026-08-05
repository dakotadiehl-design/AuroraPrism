import SwiftUI

/// Calm empty / placeholder panel body.
public struct PlaceholderPanel: View {
    public var title: String
    public var detail: String

    public init(title: String, detail: String = "") {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        AuroraEmptyState(title: title, detail: detail)
            .background(AuroraColor.surfacePanel)
    }
}
