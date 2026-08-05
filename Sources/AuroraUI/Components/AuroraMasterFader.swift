import SwiftUI

/// Horizontal labeled master (Grand Master, group masters) for Perform Mode.
public struct AuroraMasterFader: View {
    public var label: String
    @Binding public var value: Double

    public init(label: String, value: Binding<Double>) {
        self.label = label
        self._value = value
    }

    public var body: some View {
        AuroraFader(value: $value, label: label, axis: .horizontal)
            .frame(minWidth: 100)
            .auroraDensity(.performance)
    }
}
