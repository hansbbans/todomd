// Sources/TodoMDApp/Features/QuickFind/QuickFindCard.swift
import SwiftUI

struct QuickFindCard<Results: View>: View {
    @Binding var query: String
    var store: QuickFindStore
    var maxHeight: CGFloat
    var onDismiss: () -> Void
    @ViewBuilder var resultsContent: (String) -> Results

    @FocusState private var isSearchFieldFocused: Bool
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow
            Divider()
            cardContent
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
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
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
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
    // when query matches nothing (verified at RootView.swift:2873). No wrapper needed here.
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
                    ForEach(store.displayedPinned, id: \.self) { pinned in
                        pinnedRow(pinned)
                    }
                }
                if !store.displayedRecent.isEmpty {
                    sectionHeader("Recent")
                    ForEach(store.displayedRecent, id: \.self) { recent in
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

    private func pinnedRow(_ item: String) -> some View {
        Button {
            query = item
        } label: {
            HStack {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Text(item)
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

    private func recentRow(_ item: String) -> some View {
        Button {
            query = item
        } label: {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Text(item)
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
}
