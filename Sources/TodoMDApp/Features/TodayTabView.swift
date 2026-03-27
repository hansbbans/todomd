import SwiftUI

enum TodayTabLayoutRow: Equatable {
    case hero
    case calendarCard
    case inlineComposer
    case emptyState(TodayTabEmptyState)
    case section(TodaySection)
    case editableRows([TaskRecord])
}

struct TodayTabDescriptor: Equatable {
    let listID: String
    let layoutRows: [TodayTabLayoutRow]

    static func makeForRootState(
        records: [TaskRecord],
        sections: [TodaySection],
        isCalendarConnected: Bool,
        showsInlineComposer: Bool,
        isEditing: Bool
    ) -> Self {
        make(
            records: records,
            sections: sections,
            showsCalendarCard: isCalendarConnected && (!isEditing || records.isEmpty),
            showsInlineComposer: showsInlineComposer,
            isEditing: isEditing
        )
    }

    static func make(
        records: [TaskRecord],
        sections: [TodaySection],
        showsCalendarCard: Bool,
        showsInlineComposer: Bool,
        isEditing: Bool
    ) -> Self {
        if records.isEmpty {
            if showsInlineComposer {
                return Self(
                    listID: "\(BuiltInView.today.rawValue)-inline-empty",
                    layoutRows: showsCalendarCard
                        ? [.hero, .inlineComposer, .calendarCard]
                        : [.hero, .inlineComposer]
                )
            }

            return Self(
                listID: "\(BuiltInView.today.rawValue)-empty",
                layoutRows: showsCalendarCard
                    ? [.hero, .calendarCard, .emptyState(.generic)]
                    : [.hero, .emptyState(.generic)]
            )
        }

        if isEditing {
            return Self(
                listID: BuiltInView.today.rawValue,
                layoutRows: showsInlineComposer
                    ? [.hero, .inlineComposer, .editableRows(records)]
                    : [.hero, .editableRows(records)]
            )
        }

        var layoutRows: [TodayTabLayoutRow] = [.hero]
        if showsCalendarCard {
            layoutRows.append(.calendarCard)
        }
        if showsInlineComposer {
            layoutRows.append(.inlineComposer)
        }
        layoutRows.append(contentsOf: sections.map(TodayTabLayoutRow.section))

        return Self(
            listID: BuiltInView.today.rawValue,
            layoutRows: layoutRows
        )
    }
}

struct TodayTabEmptyState: Equatable {
    let title: String
    let symbol: String
    let subtitle: String

    static let generic = Self(
        title: "You're all caught up",
        symbol: "star.fill",
        subtitle: "Enjoy the rest of your day."
    )
}

struct TodayTabView<HeroRow: View, CalendarCard: View, InlineComposer: View, TaskRow: View, SummaryRow: View>: View {
    let descriptor: TodayTabDescriptor
    let onReorder: ([String]) -> Void
    private let heroRow: () -> HeroRow
    private let calendarCard: () -> CalendarCard
    private let inlineComposer: () -> InlineComposer
    private let taskRow: (TaskRecord) -> TaskRow
    private let unparseableSummary: () -> SummaryRow

    init(
        descriptor: TodayTabDescriptor,
        onReorder: @escaping ([String]) -> Void,
        @ViewBuilder heroRow: @escaping () -> HeroRow,
        @ViewBuilder calendarCard: @escaping () -> CalendarCard,
        @ViewBuilder inlineComposer: @escaping () -> InlineComposer,
        @ViewBuilder taskRow: @escaping (TaskRecord) -> TaskRow,
        @ViewBuilder unparseableSummary: @escaping () -> SummaryRow
    ) {
        self.descriptor = descriptor
        self.onReorder = onReorder
        self.heroRow = heroRow
        self.calendarCard = calendarCard
        self.inlineComposer = inlineComposer
        self.taskRow = taskRow
        self.unparseableSummary = unparseableSummary
    }

    var body: some View {
        ForEach(Array(descriptor.layoutRows.enumerated()), id: \.offset) { _, row in
            contentRow(for: row)
        }
    }

    @ViewBuilder
    private func contentRow(for row: TodayTabLayoutRow) -> some View {
        switch row {
        case .hero:
            heroRow()
        case .calendarCard:
            calendarCard()
        case .inlineComposer:
            inlineComposer()
        case .emptyState(let emptyState):
            emptyStateContent(emptyState)
        case .section(let section):
            sectionTaskRows(section)
        case .editableRows(let records):
            editableTaskRows(records)
        }
    }

    private func editableTaskRows(_ records: [TaskRecord]) -> some View {
        ForEach(records) { record in
            taskRow(record)
        }
        .onMove { source, destination in
            var reordered = records
            reordered.move(fromOffsets: source, toOffset: destination)
            onReorder(reordered.map(\.identity.filename))
        }
    }

    private func sectionTaskRows(_ section: TodaySection) -> some View {
        Section {
            ForEach(section.records) { record in
                taskRow(record)
            }
        } header: {
            SectionHeaderView(
                section.group.rawValue,
                count: section.records.count,
                systemImage: section.group == .scheduledEvening ? "moon.stars" : nil
            )
        }
    }

    private func emptyStateContent(_ emptyState: TodayTabEmptyState) -> some View {
        VStack(spacing: 12) {
            IllustratedEmptyState(
                symbol: emptyState.symbol,
                glowColor: Color(.systemYellow).opacity(0.2),
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
