import SwiftUI

struct ConflictResolutionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose which copy should win.")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(theme.textPrimaryColor)
                    Text("Review the local file and each remote version, then keep the one you trust.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    ThingsSurfaceBackdrop(
                        kind: .elevatedCard,
                        theme: theme,
                        colorScheme: colorScheme,
                        emphasis: container.conflicts.isEmpty ? .standard : .warning
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if container.conflicts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Conflicts",
                        systemImage: "checkmark.shield",
                        description: Text("Your local files and synced copies agree right now.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section("Files With Conflicts") {
                    ForEach(container.conflicts) { conflict in
                        NavigationLink {
                            ConflictDetailView(conflict: conflict)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conflict.filename)
                                            .font(.headline)
                                            .foregroundStyle(theme.textPrimaryColor)
                                        Text("Local source: \(conflict.localSource)")
                                            .font(.subheadline)
                                            .foregroundStyle(theme.textSecondaryColor)
                                    }

                                    Spacer(minLength: 12)

                                    Text("\(conflict.versions.count) remote")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.12))
                                        )
                                }

                                if let localModified = conflict.localModifiedAt {
                                    Text("Modified \(DateCoding.encode(localModified))")
                                        .font(.footnote)
                                        .foregroundStyle(theme.textSecondaryColor)
                                }

                                Text(conflict.path)
                                    .font(.caption)
                                    .foregroundStyle(theme.textTertiaryColor)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                ThingsSurfaceBackdrop(
                                    kind: .elevatedCard,
                                    theme: theme,
                                    colorScheme: colorScheme,
                                    emphasis: .warning
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle("Conflicts")
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.backgroundColor)
    }
}

private struct ConflictDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager

    let conflict: ConflictSummary
    @State private var selectedVersionID: String = ""

    private var selectedVersion: ConflictVersionSummary? {
        conflict.versions.first(where: { $0.id == selectedVersionID }) ?? conflict.versions.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(conflict.filename)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(theme.textPrimaryColor)

                    Text(conflict.path)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondaryColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Compare the local file with the remote copy you want to keep.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(
                    ThingsSurfaceBackdrop(
                        kind: .elevatedCard,
                        theme: theme,
                        colorScheme: colorScheme,
                        emphasis: .warning
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))

                if !conflict.versions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Remote Version")
                            .font(.headline)
                            .foregroundStyle(theme.textPrimaryColor)

                        Picker("Remote version", selection: $selectedVersionID) {
                            ForEach(conflict.versions) { version in
                                let modifiedLabel = version.modifiedAt.map(DateCoding.encode) ?? "Unknown date"
                                Text("\(version.savingComputer) · \(modifiedLabel)").tag(version.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Pick the remote version you want to compare against the local copy.")
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondaryColor)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(
                        ThingsSurfaceBackdrop(
                            kind: .elevatedCard,
                            theme: theme,
                            colorScheme: colorScheme
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        comparisonCard(
                            title: "Local",
                            subtitle: "Source: \(conflict.localSource)",
                            modifiedText: conflict.localModifiedAt.map { "Modified: \(DateCoding.encode($0))" },
                            contents: container.localFileContents(path: conflict.path)
                        )
                        .frame(minWidth: 280)

                        comparisonCard(
                            title: "Remote",
                            subtitle: selectedVersion.map { "Device: \($0.savingComputer)" } ?? "Remote copy",
                            modifiedText: selectedVersion?.modifiedAt.map { "Modified: \(DateCoding.encode($0))" },
                            contents: container.conflictVersionContents(atPath: selectedVersion?.versionURLPath)
                        )
                        .frame(minWidth: 280)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        comparisonCard(
                            title: "Local",
                            subtitle: "Source: \(conflict.localSource)",
                            modifiedText: conflict.localModifiedAt.map { "Modified: \(DateCoding.encode($0))" },
                            contents: container.localFileContents(path: conflict.path)
                        )

                        comparisonCard(
                            title: "Remote",
                            subtitle: selectedVersion.map { "Device: \($0.savingComputer)" } ?? "Remote copy",
                            modifiedText: selectedVersion?.modifiedAt.map { "Modified: \(DateCoding.encode($0))" },
                            contents: container.conflictVersionContents(atPath: selectedVersion?.versionURLPath)
                        )
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        keepLocalButton
                        keepRemoteButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        keepLocalButton
                        keepRemoteButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .navigationTitle("Conflict Detail")
        .background(theme.backgroundColor.ignoresSafeArea())
        .onAppear {
            if selectedVersionID.isEmpty {
                selectedVersionID = conflict.versions.first?.id ?? ""
            }
        }
    }

    private func comparisonCard(
        title: String,
        subtitle: String,
        modifiedText: String?,
        contents: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimaryColor)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondaryColor)
            if let modifiedText {
                Text(modifiedText)
                    .font(.footnote)
                    .foregroundStyle(theme.textTertiaryColor)
            }
            ScrollView {
                Text(contents)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textPrimaryColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            ThingsSurfaceBackdrop(
                kind: .elevatedCard,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
    }

    private var keepLocalButton: some View {
        Button("Keep Local", systemImage: "macwindow") {
            container.resolveConflictKeepLocal(path: conflict.path)
            dismiss()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var keepRemoteButton: some View {
        Button("Keep Selected Remote", systemImage: "icloud.and.arrow.down") {
            container.resolveConflictKeepRemote(path: conflict.path, preferredVersionID: selectedVersion?.id)
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
