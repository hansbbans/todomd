// Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
import SwiftUI

struct QuickFindCard<Results: View>: View {
    @Binding var query: String
    var store: QuickFindStore
    var maxHeight: CGFloat
    var onDismiss: () -> Void
    var onSelectRecent: (RecentItem) -> Void
    @ViewBuilder var resultsContent: (String) -> Results

    @FocusState private var isSearchFieldFocused: Bool
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var cardBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }

    private var pillBackground: Color {
#if canImport(UIKit)
        Color(uiColor: .tertiarySystemGroupedBackground)
#else
        Color(nsColor: .textBackgroundColor)
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow
            Divider()
            cardContent
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
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
                    .foregroundStyle(.secondary)
                TextField("Quick Find", text: $query)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("quickFind.searchField")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(pillBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
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
        if normalizedQuery.isEmpty {
            preQueryContent
        } else {
            List {
                resultsContent(normalizedQuery)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var preQueryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.displayedPinned.isEmpty {
                sectionHeader("Pinned")
                ForEach(store.displayedPinned, id: \.destination) { pinned in
                    pinnedRow(pinned)
                }
            }
            if !store.displayedRecent.isEmpty {
                sectionHeader("Recent")
                ForEach(store.displayedRecent, id: \.destination) { recent in
                    recentRow(recent)
                }
            }
            Text("Quickly find tasks, lists, tags…")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
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

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            Divider()
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
