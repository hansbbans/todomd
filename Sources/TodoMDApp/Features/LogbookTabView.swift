import SwiftUI

enum LogbookTabState: Equatable {
    case genericEmpty
    case searchEmpty
    case populated
}

struct LogbookSearchEmptyState: Equatable {
    let title: String
    let symbol: String
    let subtitle: String
    let exampleQuery: String

    static let generic = Self(
        title: "No logbook matches",
        symbol: "magnifyingglass",
        subtitle: "Try a broader search or filters like project:, tag:, status:, before:, or after:.",
        exampleQuery: "Examples: `project:Work`, `tag:errands`, `status:cancelled`, `before:2026-03-01`"
    )
}

struct LogbookTabDescriptor: Equatable {
    let listID: String
    let filteredRecordPaths: [String]
    let state: LogbookTabState
    let searchEmptyState: LogbookSearchEmptyState?

    static func make(records: [TaskRecord], filteredRecords: [TaskRecord]) -> Self {
        if records.isEmpty {
            return Self(
                listID: "\(BuiltInView.logbook.rawValue)-empty",
                filteredRecordPaths: [],
                state: .genericEmpty,
                searchEmptyState: nil
            )
        }

        if filteredRecords.isEmpty {
            return Self(
                listID: "\(BuiltInView.logbook.rawValue)-search-empty",
                filteredRecordPaths: [],
                state: .searchEmpty,
                searchEmptyState: .generic
            )
        }

        return Self(
            listID: BuiltInView.logbook.rawValue,
            filteredRecordPaths: filteredRecords.map(\.identity.path),
            state: .populated,
            searchEmptyState: nil
        )
    }
}

struct LogbookTabView<GenericEmptyContent: View, SearchEmptyContent: View, PopulatedContent: View>: View {
    let descriptor: LogbookTabDescriptor
    @Binding var searchText: String
    let filteredRecords: [TaskRecord]
    private let genericEmptyContent: () -> GenericEmptyContent
    private let searchEmptyContent: (LogbookSearchEmptyState) -> SearchEmptyContent
    private let populatedContent: ([TaskRecord]) -> PopulatedContent

    init(
        descriptor: LogbookTabDescriptor,
        searchText: Binding<String>,
        filteredRecords: [TaskRecord],
        @ViewBuilder genericEmptyContent: @escaping () -> GenericEmptyContent,
        @ViewBuilder searchEmptyContent: @escaping (LogbookSearchEmptyState) -> SearchEmptyContent,
        @ViewBuilder populatedContent: @escaping ([TaskRecord]) -> PopulatedContent
    ) {
        self.descriptor = descriptor
        _searchText = searchText
        self.filteredRecords = filteredRecords
        self.genericEmptyContent = genericEmptyContent
        self.searchEmptyContent = searchEmptyContent
        self.populatedContent = populatedContent
    }

    var body: some View {
        Group {
            switch descriptor.state {
            case .genericEmpty:
                genericEmptyContent()
            case .searchEmpty:
                if let searchEmptyState = descriptor.searchEmptyState {
                    searchEmptyContent(searchEmptyState)
                } else {
                    genericEmptyContent()
                }
            case .populated:
                populatedContent(filteredRecords)
            }
        }
        .searchable(
            text: $searchText,
            placement: .automatic,
            prompt: "Search title, project:, tag:, status:, before:"
        )
    }
}
