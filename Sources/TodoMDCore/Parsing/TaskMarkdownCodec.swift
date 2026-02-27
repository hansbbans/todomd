import Foundation
import Yams

public struct TaskMarkdownCodec {
    private static let maxFrontmatterDepth = 24
    private static let maxFrontmatterNodeCount = 2_000

    public init() {}

    public func parse(markdown: String, fallbackTitle: String? = nil) throws -> TaskDocument {
        let split = try splitFrontmatter(from: markdown)
        let frontmatterObject = try decodeYAMLObject(yaml: split.frontmatter)
        let normalizedObject = normalizedKnownKeyObject(from: frontmatterObject)
        try validateFrontmatterComplexity(normalizedObject)

        let knownKeys: Set<String> = [
            "title", "status", "due", "due_time", "defer", "scheduled", "priority", "flagged", "area", "project", "tags",
            "recurrence", "estimated_minutes", "description", "created", "modified", "completed", "source"
        ]

        var unknown: [String: YAMLValue] = [:]
        for (key, value) in frontmatterObject where !knownKeys.contains(key.lowercased()) {
            unknown[key] = YAMLValue(any: value)
        }

        let frontmatter = try parseFrontmatter(from: normalizedObject, fallbackTitle: fallbackTitle)
        let document = TaskDocument(frontmatter: frontmatter, body: split.body, unknownFrontmatter: unknown)
        try TaskValidation.validate(document: document)
        return document
    }

    public func serialize(document: TaskDocument) throws -> String {
        try TaskValidation.validate(document: document)

        var object: [String: Any] = [
            "title": document.frontmatter.title,
            "status": document.frontmatter.status.rawValue,
            "priority": document.frontmatter.priority.rawValue,
            "flagged": document.frontmatter.flagged,
            "created": DateCoding.encode(document.frontmatter.created),
            "source": document.frontmatter.source
        ]

        if let due = document.frontmatter.due { object["due"] = due.isoString }
        if let dueTime = document.frontmatter.dueTime { object["due_time"] = dueTime.isoString }
        if let deferDate = document.frontmatter.defer { object["defer"] = deferDate.isoString }
        if let scheduled = document.frontmatter.scheduled { object["scheduled"] = scheduled.isoString }
        if let area = document.frontmatter.area { object["area"] = area }
        if let project = document.frontmatter.project { object["project"] = project }
        if !document.frontmatter.tags.isEmpty { object["tags"] = document.frontmatter.tags }
        if let recurrence = document.frontmatter.recurrence { object["recurrence"] = recurrence }
        if let estimatedMinutes = document.frontmatter.estimatedMinutes { object["estimated_minutes"] = estimatedMinutes }
        if let description = document.frontmatter.description { object["description"] = description }
        if let modified = document.frontmatter.modified { object["modified"] = DateCoding.encode(modified) }
        if let completed = document.frontmatter.completed { object["completed"] = DateCoding.encode(completed) }

        for (key, value) in document.unknownFrontmatter {
            object[key] = value.anyValue
        }

        let yaml = try Yams.dump(object: object, sortKeys: true)
        let normalizedBody = document.body.hasSuffix("\n") ? document.body : document.body + "\n"
        return "---\n\(yaml)---\n\(normalizedBody)"
    }

    private func splitFrontmatter(from markdown: String) throws -> (frontmatter: String, body: String) {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            throw TaskError.parseFailure("Document is missing leading frontmatter delimiter")
        }

        let startIndex = normalized.index(normalized.startIndex, offsetBy: 4)
        var remainder = String(normalized[startIndex...])

        // Some legacy files contain a redundant second delimiter line (`---`).
        if remainder.hasPrefix("---\n") {
            remainder.removeFirst(4)
        }

        if let separatorRange = remainder.range(of: "\n---\n") {
            let frontmatter = String(remainder[..<separatorRange.lowerBound])
            let bodyStart = separatorRange.upperBound
            let body = String(remainder[bodyStart...])
            return (frontmatter, body)
        }

        if remainder.hasSuffix("\n---") {
            let frontmatterEnd = remainder.index(remainder.endIndex, offsetBy: -4)
            let frontmatter = String(remainder[..<frontmatterEnd])
            return (frontmatter, "")
        }

        throw TaskError.parseFailure("Document is missing closing frontmatter delimiter")
    }

    private func decodeYAMLObject(yaml: String) throws -> [String: Any] {
        let loaded = try Yams.load(yaml: yaml)
        guard let object = loaded as? [String: Any] else {
            throw TaskError.parseFailure("Frontmatter YAML is not an object")
        }
        return object
    }

    private func normalizedKnownKeyObject(from object: [String: Any]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        normalized.reserveCapacity(object.count)

        for (key, value) in object {
            let canonical = canonicalKnownKey(for: key.lowercased())
            if normalized[canonical] == nil {
                normalized[canonical] = value
            }
        }

        return normalized
    }

    private func canonicalKnownKey(for loweredKey: String) -> String {
        switch loweredKey {
        case "datecreated":
            return "created"
        case "datemodified":
            return "modified"
        case "completeddate":
            return "completed"
        default:
            return loweredKey
        }
    }

    private func validateFrontmatterComplexity(_ object: [String: Any]) throws {
        var visitedNodes = 0
        try validateNode(value: object, depth: 1, visitedNodes: &visitedNodes)
    }

    private func validateNode(value: Any, depth: Int, visitedNodes: inout Int) throws {
        if depth > Self.maxFrontmatterDepth {
            throw TaskError.parseFailure("Frontmatter nesting exceeds maximum depth (\(Self.maxFrontmatterDepth))")
        }

        visitedNodes += 1
        if visitedNodes > Self.maxFrontmatterNodeCount {
            throw TaskError.parseFailure("Frontmatter exceeds maximum node count (\(Self.maxFrontmatterNodeCount))")
        }

        if let dict = value as? [String: Any] {
            for child in dict.values {
                try validateNode(value: child, depth: depth + 1, visitedNodes: &visitedNodes)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                try validateNode(value: child, depth: depth + 1, visitedNodes: &visitedNodes)
            }
        }
    }

    private func parseFrontmatter(from object: [String: Any], fallbackTitle: String?) throws -> TaskFrontmatterV1 {
        let title = try resolvedTitle(in: object, fallbackTitle: fallbackTitle)
        let statusRaw = try optionalString("status", in: object) ?? TaskStatus.todo.rawValue
        let status = parseStatus(statusRaw)

        let due = try optionalDate("due", in: object)
        let dueTime = try optionalTime("due_time", in: object)
        let deferDate = try optionalDate("defer", in: object)
        let scheduled = try optionalDate("scheduled", in: object)

        let priorityRaw = try optionalString("priority", in: object) ?? TaskPriority.none.rawValue
        let priority = parsePriority(priorityRaw)

        let flagged = try optionalBool("flagged", in: object) ?? false
        let area = try optionalString("area", in: object)
        let project = try optionalString("project", in: object)
        let recurrence = try optionalString("recurrence", in: object)
        let estimatedMinutes = try optionalInt("estimated_minutes", in: object)
        let description = try optionalString("description", in: object)

        let tags: [String]
        if let rawTags = object["tags"] {
            if let tagValues = rawTags as? [Any] {
                tags = try tagValues.map { value in
                    guard let tag = value as? String else {
                        throw TaskError.parseFailure("Expected string tag value")
                    }
                    return tag
                }
            } else if let csv = rawTags as? String {
                tags = csv
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } else {
                throw TaskError.parseFailure("Expected array or comma-separated string for tags")
            }
        } else {
            tags = []
        }

        let created = try optionalDateTime("created", in: object) ?? Date.distantPast

        let modified = try optionalDateTime("modified", in: object)
        let completed = try optionalDateTime("completed", in: object)
        let source = try optionalString("source", in: object) ?? "unknown"

        return TaskFrontmatterV1(
            title: title,
            status: status,
            due: due,
            dueTime: dueTime,
            defer: deferDate,
            scheduled: scheduled,
            priority: priority,
            flagged: flagged,
            area: area,
            project: project,
            tags: tags,
            recurrence: recurrence,
            estimatedMinutes: estimatedMinutes,
            description: description,
            created: created,
            modified: modified,
            completed: completed,
            source: source
        )
    }

    private func resolvedTitle(in object: [String: Any], fallbackTitle: String?) throws -> String {
        if let explicit = try optionalString("title", in: object)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }

        if let fallbackTitle = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackTitle.isEmpty {
            return fallbackTitle
        }

        throw TaskError.parseFailure("Missing required field: title")
    }

    private func requireString(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] else {
            throw TaskError.parseFailure("Missing required field: \(key)")
        }
        guard let string = value as? String else {
            throw TaskError.parseFailure("Field \(key) must be a string")
        }
        return string
    }

    private func optionalString(_ key: String, in object: [String: Any]) throws -> String? {
        guard let value = object[key] else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw TaskError.parseFailure("Field \(key) must be a string")
        }
        return string
    }

    private func optionalBool(_ key: String, in object: [String: Any]) throws -> Bool? {
        guard let value = object[key] else { return nil }
        if value is NSNull { return nil }
        guard let bool = value as? Bool else {
            throw TaskError.parseFailure("Field \(key) must be a boolean")
        }
        return bool
    }

    private func optionalInt(_ key: String, in object: [String: Any]) throws -> Int? {
        guard let value = object[key] else { return nil }
        if value is NSNull { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double, floor(double) == double { return Int(double) }
        throw TaskError.parseFailure("Field \(key) must be an integer")
    }

    private func optionalDate(_ key: String, in object: [String: Any]) throws -> LocalDate? {
        guard let value = object[key] else { return nil }
        if value is NSNull { return nil }

        if let raw = value as? String {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                return nil
            }
            do {
                return try LocalDate(isoDate: normalized)
            } catch {
                throw TaskError.parseFailure("Invalid date for \(key): \(normalized)")
            }
        }

        if let date = value as? Date {
            var calendar = Calendar(identifier: .gregorian)
            if let utc = TimeZone(secondsFromGMT: 0) {
                calendar.timeZone = utc
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            do {
                return try LocalDate(
                    year: components.year ?? 1970,
                    month: components.month ?? 1,
                    day: components.day ?? 1
                )
            } catch {
                throw TaskError.parseFailure("Invalid date for \(key): \(date)")
            }
        }

        throw TaskError.parseFailure("Field \(key) must be a date string")
    }

    private func optionalDateTime(_ key: String, in object: [String: Any]) throws -> Date? {
        guard let value = object[key] else { return nil }
        if value is NSNull { return nil }

        if let date = value as? Date {
            return date
        }

        if let raw = value as? String {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                return nil
            }
            guard let date = DateCoding.decode(normalized) else {
                throw TaskError.parseFailure("Invalid datetime for \(key): \(normalized)")
            }
            return date
        }

        if let seconds = value as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }

        throw TaskError.parseFailure("Field \(key) must be a datetime string")
    }

    private func optionalTime(_ key: String, in object: [String: Any]) throws -> LocalTime? {
        guard let value = object[key] else { return nil }
        if value is NSNull { return nil }

        guard let raw = value as? String else {
            throw TaskError.parseFailure("Field \(key) must be a time string")
        }

        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return nil
        }

        do {
            return try LocalTime(isoTime: normalized)
        } catch {
            throw TaskError.parseFailure("Invalid time for \(key): \(normalized)")
        }
    }

    private func parseStatus(_ raw: String) -> TaskStatus {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "", "todo", "to-do", "open", "pending":
            return .todo
        case "in-progress", "inprogress", "doing":
            return .inProgress
        case "done", "complete", "completed":
            return .done
        case "cancelled", "canceled":
            return .cancelled
        case "someday", "maybe":
            return .someday
        default:
            return .todo
        }
    }

    private func parsePriority(_ raw: String) -> TaskPriority {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "", "none", "p4":
            return .none
        case "low", "p3":
            return .low
        case "medium", "med", "normal", "p2":
            return .medium
        case "high", "p1":
            return .high
        default:
            return .none
        }
    }
}
