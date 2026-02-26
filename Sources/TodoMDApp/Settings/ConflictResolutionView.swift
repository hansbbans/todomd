import SwiftUI

struct ConflictResolutionView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        List {
            if container.conflicts.isEmpty {
                ContentUnavailableView("No Conflicts", systemImage: "checkmark.shield")
            } else {
                ForEach(container.conflicts) { conflict in
                    NavigationLink {
                        ConflictDetailView(conflict: conflict)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.filename)
                                .font(.headline)
                            Text("Local source: \(conflict.localSource)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let localModified = conflict.localModifiedAt {
                                Text("Modified: \(DateCoding.encode(localModified))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(conflict.versions.count) remote version(s)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Conflicts")
    }
}

private struct ConflictDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer

    let conflict: ConflictSummary
    @State private var selectedVersionID: String = ""

    private var selectedVersion: ConflictVersionSummary? {
        conflict.versions.first(where: { $0.id == selectedVersionID }) ?? conflict.versions.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(conflict.filename)
                    .font(.headline)

                Text(conflict.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !conflict.versions.isEmpty {
                    Picker("Remote version", selection: $selectedVersionID) {
                        ForEach(conflict.versions) { version in
                            let modifiedLabel = version.modifiedAt.map(DateCoding.encode) ?? "Unknown date"
                            Text("\(version.savingComputer) · \(modifiedLabel)").tag(version.id)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local")
                            .font(.subheadline.bold())
                        Text("Source: \(conflict.localSource)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let localModified = conflict.localModifiedAt {
                            Text("Modified: \(DateCoding.encode(localModified))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ScrollView {
                            Text(container.localFileContents(path: conflict.path))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 220)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remote")
                            .font(.subheadline.bold())
                        if let version = selectedVersion {
                            Text("Device: \(version.savingComputer)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let modified = version.modifiedAt {
                                Text("Modified: \(DateCoding.encode(modified))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ScrollView {
                            Text(container.conflictVersionContents(atPath: selectedVersion?.versionURLPath))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 220)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("Keep Local") {
                        container.resolveConflictKeepLocal(path: conflict.path)
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Keep Selected Remote") {
                        container.resolveConflictKeepRemote(path: conflict.path, preferredVersionID: selectedVersion?.id)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle("Conflict Detail")
        .onAppear {
            if selectedVersionID.isEmpty {
                selectedVersionID = conflict.versions.first?.id ?? ""
            }
        }
    }
}
