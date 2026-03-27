import SwiftUI

enum InboxTabContentElement: Equatable {
    case hero
    case inlineComposer
    case importPanel
    case emptyState
    case taskRows
}

struct InboxTabDescriptor: Equatable {
    let listID: String
    let taskRecordPaths: [String]
    let showsInlineComposer: Bool
    let emptyState: InboxTabEmptyState?
    let contentOrder: [InboxTabContentElement]

    static func make(records: [TaskRecord], showsInlineComposer: Bool) -> Self {
        if records.isEmpty {
            return Self(
                listID: showsInlineComposer ? "\(BuiltInView.inbox.rawValue)-inline-empty" : "\(BuiltInView.inbox.rawValue)-empty",
                taskRecordPaths: [],
                showsInlineComposer: showsInlineComposer,
                emptyState: showsInlineComposer ? nil : .generic,
                contentOrder: showsInlineComposer
                    ? [.hero, .inlineComposer, .importPanel]
                    : [.hero, .importPanel, .emptyState]
            )
        }

        return Self(
            listID: BuiltInView.inbox.rawValue,
            taskRecordPaths: records.map(\.identity.path),
            showsInlineComposer: showsInlineComposer,
            emptyState: nil,
            contentOrder: showsInlineComposer
                ? [.hero, .importPanel, .inlineComposer, .taskRows]
                : [.hero, .importPanel, .taskRows]
        )
    }
}

struct InboxTabEmptyState: Equatable {
    let title: String
    let symbol: String
    let subtitle: String

    static let generic = Self(
        title: "Inbox is clear",
        symbol: "tray.fill",
        subtitle: "New tasks land here first."
    )
}

struct InboxTabView<HeroRow: View, ImportPanel: View, InlineComposer: View, TaskRow: View, SummaryRow: View>: View {
    let descriptor: InboxTabDescriptor
    let records: [TaskRecord]
    let onReorder: ([String]) -> Void
    private let heroRow: () -> HeroRow
    private let importPanel: () -> ImportPanel
    private let inlineComposer: () -> InlineComposer
    private let taskRow: (TaskRecord) -> TaskRow
    private let unparseableSummary: () -> SummaryRow

    init(
        descriptor: InboxTabDescriptor,
        records: [TaskRecord],
        onReorder: @escaping ([String]) -> Void,
        @ViewBuilder heroRow: @escaping () -> HeroRow,
        @ViewBuilder importPanel: @escaping () -> ImportPanel,
        @ViewBuilder inlineComposer: @escaping () -> InlineComposer,
        @ViewBuilder taskRow: @escaping (TaskRecord) -> TaskRow,
        @ViewBuilder unparseableSummary: @escaping () -> SummaryRow
    ) {
        self.descriptor = descriptor
        self.records = records
        self.onReorder = onReorder
        self.heroRow = heroRow
        self.importPanel = importPanel
        self.inlineComposer = inlineComposer
        self.taskRow = taskRow
        self.unparseableSummary = unparseableSummary
    }

    var body: some View {
        ForEach(Array(descriptor.contentOrder.enumerated()), id: \.offset) { _, element in
            contentRow(for: element)
        }
    }

    @ViewBuilder
    private func contentRow(for element: InboxTabContentElement) -> some View {
        switch element {
        case .hero:
            heroRow()
        case .inlineComposer:
            inlineComposer()
        case .importPanel:
            importPanel()
        case .emptyState:
            if let emptyState = descriptor.emptyState {
                emptyStateContent(emptyState)
            }
        case .taskRows:
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

    private func emptyStateContent(_ emptyState: InboxTabEmptyState) -> some View {
        VStack(spacing: 12) {
            IllustratedEmptyState(
                symbol: emptyState.symbol,
                glowColor: Color.accentColor.opacity(0.18),
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
    }
}
