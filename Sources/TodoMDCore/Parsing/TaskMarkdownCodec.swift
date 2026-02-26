import Foundation
import Yams

public struct TaskMarkdownCodec {
    private static let maxFrontmatterDepth = 24
    private static let maxFrontmatterNodeCount = 2_000

    public init() {}

    public func parse(markdown: String) throws -> TaskDocument {
        let split = try splitFrontmatter(from: markdown)
        let frontmatterObject = try decodeYAMLObject(yaml: split.frontmatter)
        try validateFrontmatterComplexity(frontmatterObject)

        let knownKeys: Set<String> = [
            "title", "status", "due", "defer", "scheduled", "priority", "flagged", "area", "project", "tags",
            "recurrence", "estimated_minutes", "description", "created", "modified", "completed", "source"
        ]

        var unknown: [String: YAMLValue] = [:]
        for (key, value) in frontmatterObject where !knownKeys.contains(key) {
            unknown[key] = YAMLValue(any: value)
        }

        let frontmatter = try parseFrontmatter(from: frontmatterObject)
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
        let remainder = String(normalized[startIndex...])

        guard let separatorRange = remainder.range(of: "\n---\n") else {
            throw TaskError.parseFailure("Document is missing closing frontmatter delimiter")
        }

        let frontmatter = String(remainder[..<separatorRange.lowerBound])
        let bodyStart = separatorRange.upperBound
        let body = String(remainder[bodyStart...])

        return (frontmatter, body)
    }

    private func decodeYAMLObject(yaml: String) throws -> [String: Any] {
        let loaded = try Yams.load(yaml: yaml)
        guard let object = loaded as? [String: Any] else {
            throw TaskError.parseFailure("Frontmatter YAML is not an object")
        }
        return object
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

    private func parseFrontmatter(from object: [String: Any]) throws -> TaskFrontmatterV1 {
        let title = try requireString("title", in: object)
        let statusRaw = try requireString("status", in: object)
        guard let status = TaskStatus(rawValue: statusRaw) else {
            throw TaskError.parseFailure("Invalid status value: \(statusRaw)")
        }

        let due = try optionalDate("due", in: object)
        let deferDate = try optionalDate("defer", in: object)
        let scheduled = try optionalDate("scheduled", in: object)

        let priorityRaw = try optionalString("priority", in: object) ?? TaskPriority.none.rawValue
        guard let priority = TaskPriority(rawValue: priorityRaw) else {
            throw TaskError.parseFailure("Invalid priority value: \(priorityRaw)")
        }

        let flagged = try optionalBool("flagged", in: object) ?? false
        let area = try optionalString("area", in: object)
        let project = try optionalString("project", in: object)
        let recurrence = try optionalString("recurrence", in: object)
        let estimatedMinutes = try optionalInt("estimated_minutes", in: object)
        let description = try optionalString("description", in: object)

        let tags: [String]
        if let rawTags = object["tags"] {
            guard let tagValues = rawTags as? [Any] else {
                throw TaskError.parseFailure("Expected array for tags")
            }
            tags = try tagValues.map { value in
                guard let tag = value as? String else {
                    throw TaskError.parseFailure("Expected string tag value")
                }
                return tag
            }
        } else {
            tags = []
        }

        let createdRaw = try requireString("created", in: object)
        guard let created = DateCoding.decode(createdRaw) else {
            throw TaskError.parseFailure("Invalid created datetime: \(createdRaw)")
        }

        let modified = try optionalDateTime("modified", in: object)
        let completed = try optionalDateTime("completed", in: object)
        let source = try requireString("source", in: object)

        return TaskFrontmatterV1(
            title: title,
            status: status,
            due: due,
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
        guard let raw = try optionalString(key, in: object) else { return nil }
        do {
            return try LocalDate(isoDate: raw)
        } catch {
            throw TaskError.parseFailure("Invalid date for \(key): \(raw)")
        }
    }

    private func optionalDateTime(_ key: String, in object: [String: Any]) throws -> Date? {
        guard let raw = try optionalString(key, in: object) else { return nil }
        guard let date = DateCoding.decode(raw) else {
            throw TaskError.parseFailure("Invalid datetime for \(key): \(raw)")
        }
        return date
    }
}
