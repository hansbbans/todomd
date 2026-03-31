import SwiftUI

struct UnparseableFilesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppContainer.self) private var container
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These files could not be read as tasks.")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(theme.textPrimaryColor)
                    Text("Fix the file outside the app or remove it here if it should no longer be part of the workspace.")
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
                        emphasis: container.diagnostics.isEmpty ? .standard : .warning
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.elevatedCard.cornerRadius, style: .continuous))
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if container.diagnostics.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Unparseable Files",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Every Markdown file in the workspace was parsed successfully.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section("Unreadable Files") {
                    ForEach(container.diagnostics, id: \.path) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(URL(fileURLWithPath: item.path).lastPathComponent)
                                .font(.headline)
                                .foregroundStyle(theme.textPrimaryColor)
                            Text(item.path)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondaryColor)
                                .textSelection(.enabled)
                            Text(item.reason)
                                .font(.subheadline)
                                .foregroundStyle(theme.textSecondaryColor)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Delete File", systemImage: "trash") {
                                container.deleteUnparseable(path: item.path)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
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
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .appTrailingAction) {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    container.refresh()
                }
            }
        }
        .navigationTitle("Unparseable")
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.backgroundColor)
    }
}
