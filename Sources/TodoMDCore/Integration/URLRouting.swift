import Foundation

public enum URLAction: Equatable, Sendable {
    case addTask(TaskCreateRequest)
    case showView(ViewIdentifier)
}

public struct TaskCreateRequest: Equatable, Sendable {
    public var title: String
    public var due: LocalDate?
    public var deferDate: LocalDate?
    public var scheduled: LocalDate?
    public var priority: TaskPriority?
    public var area: String?
    public var project: String?
    public var tags: [String]
    public var source: String

    public init(
        title: String,
        due: LocalDate? = nil,
        deferDate: LocalDate? = nil,
        scheduled: LocalDate? = nil,
        priority: TaskPriority? = nil,
        area: String? = nil,
        project: String? = nil,
        tags: [String] = [],
        source: String = "shortcut"
    ) {
        self.title = title
        self.due = due
        self.deferDate = deferDate
        self.scheduled = scheduled
        self.priority = priority
        self.area = area
        self.project = project
        self.tags = tags
        self.source = source
    }
}

public struct URLRouter {
    public init() {}

    public func parse(url: URL) throws -> URLAction {
        guard url.scheme?.lowercased() == "todomd" else {
            throw TaskError.unsupportedURLAction("Unsupported scheme")
        }

        if url.host == "add" {
            return try .addTask(parseAddTask(url: url))
        }

        if url.host == "show" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty else {
                throw TaskError.invalidURLParameters("Missing view identifier")
            }
            return .showView(ViewIdentifier(rawValue: path))
        }

        throw TaskError.unsupportedURLAction("Unsupported action host: \(url.host ?? "<none>")")
    }

    private func parseAddTask(url: URL) throws -> TaskCreateRequest {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TaskError.invalidURLParameters("Could not parse URL components")
        }

        let queryItems = components.percentEncodedQueryItems ?? components.queryItems ?? []
        let title = (decodeQueryValue(queryItems.first(where: { $0.name == "title" })?.value) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            throw TaskError.invalidURLParameters("Missing title parameter")
        }

        let due = try parseDate(named: "due", from: queryItems)
        let deferDate = try parseDate(named: "defer", from: queryItems)
        let scheduled = try parseDate(named: "scheduled", from: queryItems)

        let priority: TaskPriority?
        if let value = decodeQueryValue(queryItems.first(where: { $0.name == "priority" })?.value) {
            priority = TaskPriority(rawValue: value)
        } else {
            priority = nil
        }

        let area = decodeQueryValue(queryItems.first(where: { $0.name == "area" })?.value)
        let project = decodeQueryValue(queryItems.first(where: { $0.name == "project" })?.value)

        let tags = decodeQueryValue(queryItems.first(where: { $0.name == "tags" })?.value)?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return TaskCreateRequest(
            title: title,
            due: due,
            deferDate: deferDate,
            scheduled: scheduled,
            priority: priority,
            area: area,
            project: project,
            tags: tags,
            source: "shortcut"
        )
    }

    private func parseDate(named key: String, from items: [URLQueryItem]) throws -> LocalDate? {
        guard let raw = decodeQueryValue(items.first(where: { $0.name == key })?.value), !raw.isEmpty else {
            return nil
        }
        do {
            return try LocalDate(isoDate: raw)
        } catch {
            throw TaskError.invalidURLParameters("Invalid \(key) date: \(raw)")
        }
    }

    private func decodeQueryValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let plusDecoded = raw.replacingOccurrences(of: "+", with: " ")
        return plusDecoded.removingPercentEncoding ?? plusDecoded
    }
}
