import SwiftUI

struct UnparseableFilesView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        List {
            if container.diagnostics.isEmpty {
                ContentUnavailableView("No Unparseable Files", systemImage: "doc.badge.gearshape")
            } else {
                ForEach(container.diagnostics, id: \.path) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.path)
                            .font(.caption)
                            .textSelection(.enabled)
                        Text(item.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button("Delete File") {
                            container.deleteUnparseable(path: item.path)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan") {
                    container.refresh()
                }
            }
        }
        .navigationTitle("Unparseable")
    }
}
