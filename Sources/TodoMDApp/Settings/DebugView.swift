import SwiftUI

struct DebugView: View {
    @EnvironmentObject private var container: AppContainer
    private let widgetDiagnostic = TaskFolderPreferences.lastWidgetLoadDiagnostic()

    var body: some View {
        Form {
            Section("Counters") {
                LabeledContent("Total files", value: "\(container.counters.totalFilesIndexed)")
                LabeledContent("Parse failures", value: "\(container.counters.parseFailureCount)")
                LabeledContent("Pending notifications", value: "\(container.counters.pendingNotificationCount)")
                LabeledContent("Conflicts", value: "\(container.conflicts.count)")
                LabeledContent("Last sync", value: container.counters.lastSync.map(DateCoding.encode) ?? "Never")
            }

            Section("Performance (ms)") {
                LabeledContent("Enumerate", value: String(format: "%.2f", container.counters.enumerateMilliseconds))
                LabeledContent("Parse", value: String(format: "%.2f", container.counters.parseMilliseconds))
                LabeledContent("Index", value: String(format: "%.2f", container.counters.indexMilliseconds))
                LabeledContent("Query", value: String(format: "%.2f", container.counters.queryMilliseconds))
            }

            Section("Diagnostics") {
                if container.diagnostics.isEmpty {
                    Text("No diagnostics")
                } else {
                    ForEach(container.diagnostics, id: \.path) { item in
                        VStack(alignment: .leading) {
                            Text(item.path)
                                .font(.caption)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Widget") {
                if let widgetDiagnostic {
                    LabeledContent("Last widget error", value: widgetDiagnostic.message)
                    if let context = widgetDiagnostic.context {
                        LabeledContent("Context", value: context)
                    }
                    LabeledContent("Timestamp", value: widgetDiagnostic.timestamp.map(DateCoding.encode) ?? "Unknown")
                } else {
                    Text("No widget load errors")
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
