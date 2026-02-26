import Foundation

public struct ManualOrderService {
    private let rootURL: URL
    private let repository: OrderRepository

    public init(rootURL: URL, repository: OrderRepository = OrderRepository()) {
        self.rootURL = rootURL
        self.repository = repository
    }

    public func ordered(records: [TaskRecord], view: ViewIdentifier) -> [TaskRecord] {
        guard let orderDocument = try? repository.load(rootURL: rootURL) else {
            return records.sorted { $0.document.frontmatter.created > $1.document.frontmatter.created }
        }

        let key = view.rawValue
        guard let orderedFilenames = orderDocument.views[key], !orderedFilenames.isEmpty else {
            return records.sorted { $0.document.frontmatter.created > $1.document.frontmatter.created }
        }

        let indexByFilename = Dictionary(uniqueKeysWithValues: orderedFilenames.enumerated().map { ($1, $0) })

        return records.sorted { lhs, rhs in
            let leftIndex = indexByFilename[lhs.identity.filename]
            let rightIndex = indexByFilename[rhs.identity.filename]

            switch (leftIndex, rightIndex) {
            case let (l?, r?):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.document.frontmatter.created > rhs.document.frontmatter.created
            }
        }
    }

    public func saveOrder(view: ViewIdentifier, filenames: [String]) throws {
        var orderDocument = try repository.load(rootURL: rootURL)
        orderDocument.views[view.rawValue] = filenames
        try repository.save(orderDocument, rootURL: rootURL)
    }
}
