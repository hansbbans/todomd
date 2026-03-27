import SwiftUI

enum ReviewProjectSummaryFormatter {
    static func makeText(_ summary: WeeklyReviewProjectSummary) -> String {
        var parts = ["\(summary.taskCount) open"]
        if summary.blockedCount > 0 {
            parts.append("\(summary.blockedCount) blocked")
        }
        if summary.delegatedCount > 0 {
            parts.append("\(summary.delegatedCount) delegated")
        }
        if summary.deferredCount > 0 {
            parts.append("\(summary.deferredCount) deferred")
        }
        if summary.somedayCount > 0 {
            parts.append("\(summary.somedayCount) someday")
        }
        parts.append("no current next action")
        return parts.joined(separator: "  ·  ")
    }
}

struct ReviewTabDescriptor: Equatable {
    let listID: String
    let clearState: ReviewTabClearState?
    let sections: [ReviewTabSectionDescriptor]

    var showsClearState: Bool { clearState != nil }

    static func make(sections: [WeeklyReviewSection]) -> Self {
        Self(
            listID: BuiltInView.review.rawValue,
            clearState: sections.isEmpty ? .reviewIsClear : nil,
            sections: sections.map(ReviewTabSectionDescriptor.init)
        )
    }
}

struct ReviewTabClearState: Equatable {
    let title: String
    let systemImage: String
    let description: String

    static let reviewIsClear = Self(
        title: "Review Is Clear",
        systemImage: "checkmark.circle",
        description: "Nothing is stale, overdue, deferred into someday, or missing a next action."
    )
}

struct ReviewTabSectionDescriptor: Equatable, Identifiable {
    let section: WeeklyReviewSection
    let title: String
    let count: Int
    let taskRecordPaths: [String]
    let projectRows: [ReviewProjectRowDescriptor]

    init(_ section: WeeklyReviewSection) {
        self.section = section
        self.title = section.kind.title
        self.count = section.count
        switch section.kind {
        case .projectsWithoutNextAction:
            self.taskRecordPaths = []
            self.projectRows = section.projects.map(ReviewProjectRowDescriptor.init)
        case .overdue, .stale, .someday:
            self.taskRecordPaths = section.records.map(\.identity.path)
            self.projectRows = []
        }
    }

    var id: String { section.id }
}

struct ReviewProjectRowDescriptor: Equatable, Identifiable {
    let project: String
    let summaryText: String

    init(_ summary: WeeklyReviewProjectSummary) {
        self.project = summary.project
        self.summaryText = ReviewProjectSummaryFormatter.makeText(summary)
    }

    init(project: String, summaryText: String) {
        self.project = project
        self.summaryText = summaryText
    }

    var id: String { project }
}

struct ReviewTabView<HeroRow: View, TaskRow: View>: View {
    let sections: [WeeklyReviewSection]
    let backgroundColor: Color
    let textPrimaryColor: Color
    let textSecondaryColor: Color
    let accentColor: Color
    let isPullToSearchEnabled: Bool
    let onSearchTrigger: () -> Void
    let onSelectProject: (String) -> Void
    let projectIcon: (String) -> String
    let projectColor: (String) -> Color?
    private let heroRow: () -> HeroRow
    private let taskRow: (TaskRecord) -> TaskRow

    init(
        sections: [WeeklyReviewSection],
        backgroundColor: Color,
        textPrimaryColor: Color,
        textSecondaryColor: Color,
        accentColor: Color,
        isPullToSearchEnabled: Bool,
        onSearchTrigger: @escaping () -> Void,
        onSelectProject: @escaping (String) -> Void,
        projectIcon: @escaping (String) -> String,
        projectColor: @escaping (String) -> Color?,
        @ViewBuilder heroRow: @escaping () -> HeroRow,
        @ViewBuilder taskRow: @escaping (TaskRecord) -> TaskRow
    ) {
        self.sections = sections
        self.backgroundColor = backgroundColor
        self.textPrimaryColor = textPrimaryColor
        self.textSecondaryColor = textSecondaryColor
        self.accentColor = accentColor
        self.isPullToSearchEnabled = isPullToSearchEnabled
        self.onSearchTrigger = onSearchTrigger
        self.onSelectProject = onSelectProject
        self.projectIcon = projectIcon
        self.projectColor = projectColor
        self.heroRow = heroRow
        self.taskRow = taskRow
    }

    var body: some View {
        let descriptor = ReviewTabDescriptor.make(sections: sections)

        List {
            heroRow()

            if let clearState = descriptor.clearState {
                ContentUnavailableView(
                    clearState.title,
                    systemImage: clearState.systemImage,
                    description: Text(clearState.description)
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(descriptor.sections) { section in
                    Section {
                        switch section.section.kind {
                        case .projectsWithoutNextAction:
                            ForEach(section.projectRows) { row in
                                ReviewProjectRow(
                                    project: row.project,
                                    summaryText: row.summaryText,
                                    icon: projectIcon(row.project),
                                    tint: projectColor(row.project) ?? accentColor,
                                    textPrimaryColor: textPrimaryColor,
                                    textSecondaryColor: textSecondaryColor,
                                    onSelectProject: onSelectProject
                                )
                            }
                        case .overdue, .stale, .someday:
                            ForEach(section.section.records) { record in
                                taskRow(record)
                            }
                        }
                    } header: {
                        SectionHeaderView(section.title, count: section.count)
                    }
                }
            }
        }
        .id(descriptor.listID)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .modifier(
            RootPullToSearchGestureModifier(
                isEnabled: isPullToSearchEnabled,
                onTrigger: onSearchTrigger
            )
        )
    }
}

private struct ReviewProjectRow: View {
    let project: String
    let summaryText: String
    let icon: String
    let tint: Color
    let textPrimaryColor: Color
    let textSecondaryColor: Color
    let onSelectProject: (String) -> Void

    var body: some View {
        Button {
            onSelectProject(project)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AppIconGlyph(
                    icon: icon,
                    fallbackSymbol: "folder",
                    pointSize: 18,
                    weight: .semibold,
                    tint: tint
                )
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project)
                        .font(.body)
                        .foregroundStyle(textPrimaryColor)
                        .lineLimit(2)

                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(textSecondaryColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondaryColor)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
#if os(iOS)
        .modifier(RootListContentBoundaryReporter())
#endif
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
