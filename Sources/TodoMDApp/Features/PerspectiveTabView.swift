import SwiftUI

struct PerspectiveTabDescriptor: Equatable {
    let listID: String
    let taskRecordPaths: [String]
    let showsInlineComposer: Bool
    let emptyState: PerspectiveTabEmptyState?

    static func make(
        view: ViewIdentifier,
        records: [TaskRecord],
        showsInlineComposer: Bool
    ) -> Self {
        let isEmpty = records.isEmpty
        return Self(
            listID: isEmpty
                ? "\(view.rawValue)-\(showsInlineComposer ? "inline-empty" : "empty")"
                : view.rawValue,
            taskRecordPaths: records.map(\.identity.path),
            showsInlineComposer: showsInlineComposer,
            emptyState: isEmpty && !showsInlineComposer ? .generic : nil
        )
    }
}

struct PerspectiveTabEmptyState: Equatable {
    let title: String
    let symbol: String
    let subtitle: String

    static let generic = Self(
        title: "Nothing here",
        symbol: "checkmark.circle",
        subtitle: "Tap + to add a task."
    )
}

struct PerspectiveTabView<HeroRow: View, InlineComposer: View, TaskRow: View, SummaryRow: View>: View {
    let descriptor: PerspectiveTabDescriptor
    let records: [TaskRecord]
    let onReorder: ([String]) -> Void
    private let heroRow: () -> HeroRow
    private let inlineComposer: () -> InlineComposer
    private let taskRow: (TaskRecord) -> TaskRow
    private let unparseableSummary: () -> SummaryRow

    init(
        descriptor: PerspectiveTabDescriptor,
        records: [TaskRecord],
        onReorder: @escaping ([String]) -> Void,
        @ViewBuilder heroRow: @escaping () -> HeroRow,
        @ViewBuilder inlineComposer: @escaping () -> InlineComposer,
        @ViewBuilder taskRow: @escaping (TaskRecord) -> TaskRow,
        @ViewBuilder unparseableSummary: @escaping () -> SummaryRow
    ) {
        self.descriptor = descriptor
        self.records = records
        self.onReorder = onReorder
        self.heroRow = heroRow
        self.inlineComposer = inlineComposer
        self.taskRow = taskRow
        self.unparseableSummary = unparseableSummary
    }

    var body: some View {
        heroRow()

        if descriptor.showsInlineComposer {
            inlineComposer()
        }

        if let emptyState = descriptor.emptyState {
            VStack(spacing: 12) {
                IllustratedEmptyState(
                    symbol: emptyState.symbol,
                    glowColor: Color.teal.opacity(0.15),
                    title: emptyState.title,
                    subtitle: emptyState.subtitle
                )
                unparseableSummary()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, ThingsSurfaceLayout.emptyStateTopPadding)
            .padding(.bottom, ThingsSurfaceLayout.emptyStateBottomPadding)
#if os(iOS)
            .modifier(RootListContentBoundaryReporter())
#endif
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(records) { record in
                taskRow(record)
            }
            .onMove { source, destination in
                var reordered = records
                reordered.move(fromOffsets: source, toOffset: destination)
                onReorder(reordered.map(\.identity.filename))
            }
        }
    }
}
