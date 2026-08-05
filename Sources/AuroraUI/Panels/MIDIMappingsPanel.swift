import AuroraCore
import AuroraMIDI
import AuroraModel
import SwiftUI

public struct MIDIMappingsPanel: View {
    public var context: WorkspacePanelContext
    public var isLearning: Bool
    public var onLearn: (ShowAction) -> Void
    public var onCancelLearn: () -> Void
    public var onChanged: () -> Void

    public init(
        context: WorkspacePanelContext,
        isLearning: Bool,
        onLearn: @escaping (ShowAction) -> Void,
        onCancelLearn: @escaping () -> Void,
        onChanged: @escaping () -> Void = {}
    ) {
        self.context = context
        self.isLearning = isLearning
        self.onLearn = onLearn
        self.onCancelLearn = onCancelLearn
        self.onChanged = onChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MIDI Mappings").font(.headline)
            if isLearning {
                HStack {
                    Text("Learning… send a MIDI message")
                        .foregroundStyle(.orange)
                    Button("Cancel") { onCancelLearn() }
                }
            } else {
                HStack {
                    Button("Learn Go") { onLearn(.go) }
                    Button("Learn Stop") { onLearn(.stop) }
                    Button("Learn Back") { onLearn(.back) }
                    Button("Learn Int CC") { onLearn(.programmerAttribute("intensity")) }
                }
                .buttonStyle(.bordered)
            }
            List(context.project.midiMappings) { mapping in
                HStack {
                    VStack(alignment: .leading) {
                        Text(mapping.action)
                        Text("\(mapping.messageType) d1=\(mapping.data1.map(String.init) ?? "-")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete", role: .destructive) {
                        try? context.session.perform(RemoveMIDIMappingCommand(mappingID: mapping.id))
                        onChanged()
                    }
                }
            }
        }
        .padding(8)
    }
}
