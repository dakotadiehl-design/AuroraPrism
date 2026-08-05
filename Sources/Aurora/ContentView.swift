import AuroraModel
import AuroraUI
import SwiftUI

/// Scaffold UI: linked modules + in-memory sample project summary (no document browser yet).
struct ContentView: View {
    private let modules = ScaffoldModuleCatalog.modules
    private let sampleProject = ShowProject.sample()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aurora")
                    .font(.largeTitle.weight(.semibold))
                Text("PR2 domain model")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Sample project")
                    .font(.headline)
                Text(sampleProject.metadata.name)
                    .font(.body)
                Text(
                    "\(sampleProject.fixtures.count) fixture(s) · \(sampleProject.cueLists.count) cue list(s) · schema v\(sampleProject.schemaVersion)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Linked modules")
                .font(.headline)

            List(modules, id: \.name) { module in
                HStack {
                    Text(module.name)
                        .font(.body.monospaced())
                    Spacer()
                    Text(module.version)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160)
            .listStyle(.inset)

            Text("Package open/save API is in AuroraModel; document UI arrives later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    ContentView()
}
