import AuroraUI
import SwiftUI

/// PR1 scaffold UI: proves the app links libraries. No show/document features yet.
struct ContentView: View {
    private let modules = ScaffoldModuleCatalog.modules

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aurora")
                    .font(.largeTitle.weight(.semibold))
                Text("PR1 scaffold")
                    .font(.title3)
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
            .frame(minHeight: 180)
            .listStyle(.inset)

            Text("Domain model, engine, and MIDI land in later PRs.")
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
