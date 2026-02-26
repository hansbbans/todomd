import Foundation

public enum TaskValidationError: Error, Equatable, Sendable {
    case requiredFieldMissing(String)
    case fieldTooLong(field: String, limit: Int)
    case invalidRange(field: String, min: Int, max: Int)
    case invalidFieldValue(field: String, value: String)
}

public enum TaskValidation {
    public static let maxTitleLength = 500
    public static let maxDescriptionLength = 2_000
    public static let maxBodyLength = 100_000
    public static let maxTagsCount = 100
    public static let maxTagLength = 80

    public static func validate(document: TaskDocument) throws {
        try validate(frontmatter: document.frontmatter)

        if document.body.count > maxBodyLength {
            throw TaskValidationError.fieldTooLong(field: "body", limit: maxBodyLength)
        }
    }

    public static func validate(frontmatter: TaskFrontmatterV1) throws {
        let title = frontmatter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            throw TaskValidationError.requiredFieldMissing("title")
        }

        if title.count > maxTitleLength {
            throw TaskValidationError.fieldTooLong(field: "title", limit: maxTitleLength)
        }

        if let description = frontmatter.description, description.count > maxDescriptionLength {
            throw TaskValidationError.fieldTooLong(field: "description", limit: maxDescriptionLength)
        }

        if frontmatter.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TaskValidationError.requiredFieldMissing("source")
        }

        if let estimatedMinutes = frontmatter.estimatedMinutes,
           !(0...100_000).contains(estimatedMinutes) {
            throw TaskValidationError.invalidRange(field: "estimated_minutes", min: 0, max: 100_000)
        }

        if frontmatter.tags.count > maxTagsCount {
            throw TaskValidationError.invalidRange(field: "tags_count", min: 0, max: maxTagsCount)
        }

        for tag in frontmatter.tags where tag.count > maxTagLength {
            throw TaskValidationError.fieldTooLong(field: "tag", limit: maxTagLength)
        }
    }
}
