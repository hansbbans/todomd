import SwiftUI

struct SomedayTabDescriptor: Equatable {
    let listID: String
    let taskRecordPaths: [String]
    let emptyState: SomedayTabEmptyState?

    static func make(records: [TaskRecord]) -> Self {
        let isEmpty = records.isEmpty
        return Self(
            listID: isEmpty ? "\(BuiltInView.someday.rawValue)-empty" : BuiltInView.someday.rawValue,
            taskRecordPaths: records.map(\.identity.path),
            emptyState: isEmpty ? .generic : nil
        )
    }
}

struct SomedayTabEmptyState: Equatable {
    let title: String
    let symbol: String
    let subtitle: String

    static let generic = Self(
        title: "Nothing here",
        symbol: "checkmark.circle",
        subtitle: "Tap + to add a task."
    )
}

struct SomedayTabView<HeroRow: View, TaskRow: View, SummaryRow: View>: View {
    let descriptor: SomedayTabDescriptor
    let records: [TaskRecord]
    let onReorder: ([String]) -> Void
    private let heroRow: () -> HeroRow
    private let taskRow: (TaskRecord) -> TaskRow
    private let unparseableSummary: () -> SummaryRow

    init(
        descriptor: SomedayTabDescriptor,
        records: [TaskRecord],
        onReorder: @escaping ([String]) -> Void,
        @ViewBuilder heroRow: @escaping () -> HeroRow,
        @ViewBuilder taskRow: @escaping (TaskRecord) -> TaskRow,
        @ViewBuilder unparseableSummary: @escaping () -> SummaryRow
    ) {
        self.descriptor = descriptor
        self.records = records
        self.onReorder = onReorder
        self.heroRow = heroRow
        self.taskRow = taskRow
        self.unparseableSummary = unparseableSummary
    }

    var body: some View {
        heroRow()

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
