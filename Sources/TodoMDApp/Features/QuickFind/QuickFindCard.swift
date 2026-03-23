// Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
import SwiftUI

struct QuickFindCard<Results: View, SuggestedContent: View>: View {
    @Binding var query: String
    var store: QuickFindStore
    var maxHeight: CGFloat
    var hasSuggestedContent: Bool
    var onDismiss: () -> Void
    var onSelectRecent: (RecentItem) -> Void
    @ViewBuilder var suggestedContent: () -> SuggestedContent
    @ViewBuilder var resultsContent: (String) -> Results

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow
            Divider()
            cardContent
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(
            ThingsSurfaceBackdrop(
                kind: .floatingPanel,
                theme: theme,
                colorScheme: colorScheme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.floatingPanel.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("quickFind.modal")
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isSearchFieldFocused = true
            }
        }
    }

    // MARK: - Search field

    private var searchFieldRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.textSecondaryColor)
                TextField("Quick Find", text: $query)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("quickFind.searchField")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                ThingsSurfaceBackdrop(
                    kind: .inset,
                    theme: theme,
                    colorScheme: colorScheme
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: ThingsSurfaceKind.inset.cornerRadius, style: .continuous))

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.textSecondaryColor)
            }
            .accessibilityLabel("Close Quick Find")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Card body

    // Note: rootSearchResultsContent already renders ContentUnavailableView("No Results", ...)
    // when query matches nothing. No wrapper needed here.
    @ViewBuilder
    private var cardContent: some View {
        List {
            if normalizedQuery.isEmpty {
                preQueryContent
            } else {
                resultsContent(normalizedQuery)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var preQueryContent: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jump back in")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(theme.textPrimaryColor)
                    Text("Open a list, return to something recent, or pick up the next task.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondaryColor)
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 14))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            suggestedContent()

            if !store.displayedPinned.isEmpty {
                Section("Pinned") {
                    ForEach(store.displayedPinned, id: \.destination) { pinned in
                        pinnedRow(pinned)
                    }
                }
            }

            if !store.displayedRecent.isEmpty {
                Section("Recent") {
                    ForEach(store.displayedRecent, id: \.destination) { recent in
                        recentRow(recent)
                    }
                }
            }

            if !hasSuggestedContent && store.displayedPinned.isEmpty && store.displayedRecent.isEmpty {
                Text("Quickly find tasks, lists, tags…")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Rows

    private func pinnedRow(_ item: RecentItem) -> some View {
        Button {
            onSelectRecent(item)
        } label: {
            HStack {
                AppIconGlyph(
                    icon: item.icon,
                    fallbackSymbol: "magnifyingglass",
                    pointSize: 16,
                    weight: .regular,
                    tint: color(forHex: item.tintHex)
                )
                Text(item.label)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Unpin") {
                store.unpin(item)
            }
            .tint(.gray)
        }
        .contextMenu {
            Button("Unpin") { store.unpin(item) }
        }
    }

    private func recentRow(_ item: RecentItem) -> some View {
        Button {
            onSelectRecent(item)
        } label: {
            HStack {
                AppIconGlyph(
                    icon: item.icon,
                    fallbackSymbol: "magnifyingglass",
                    pointSize: 16,
                    weight: .regular,
                    tint: color(forHex: item.tintHex)
                )
                Text(item.label)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Pin") {
                if store.isPinFull {
#if canImport(UIKit)
                    Task { @MainActor in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
#endif
                } else {
                    store.pin(item)
                }
            }
            .tint(store.isPinFull ? .gray : .blue)
        }
        .contextMenu {
            Button("Pin") {
                store.pin(item)
            }
            .disabled(store.isPinFull)
            Button("Delete", role: .destructive) {
                store.deleteRecent(item)
            }
        }
    }

    // MARK: - Color helper

    private func color(forHex hex: String?) -> Color? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        return Color(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}
