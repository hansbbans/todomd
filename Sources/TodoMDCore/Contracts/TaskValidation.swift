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
    public static let maxLocationNameLength = 200
    public static let maxBodyLength = 100_000
    public static let maxIdentityLength = 120
    public static let maxBlockedRefsCount = 50
    public static let maxTagsCount = 100
    public static let maxTagLength = 80

    public static func validate(document: TaskDocument) throws {
        try validate(frontmatter: document.frontmatter)

        if document.body.count > maxBodyLength {
            throw TaskValidationError.fieldTooLong(field: "body", limit: maxBodyLength)
        }
    }

    public static func validate(frontmatter: TaskFrontmatterV1) throws {
        if let ref = frontmatter.ref {
            let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw TaskValidationError.invalidFieldValue(field: "ref", value: "ref must not be empty")
            }
            if trimmed.count > maxIdentityLength {
                throw TaskValidationError.fieldTooLong(field: "ref", limit: maxIdentityLength)
            }
            if !isValidTaskRef(trimmed) {
                throw TaskValidationError.invalidFieldValue(field: "ref", value: "ref must match t-[0-9a-f]{4,6}")
            }
        }

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

        if let assignee = frontmatter.assignee,
           assignee.trimmingCharacters(in: .whitespacesAndNewlines).count > maxIdentityLength {
            throw TaskValidationError.fieldTooLong(field: "assignee", limit: maxIdentityLength)
        }

        if let completedBy = frontmatter.completedBy,
           completedBy.trimmingCharacters(in: .whitespacesAndNewlines).count > maxIdentityLength {
            throw TaskValidationError.fieldTooLong(field: "completed_by", limit: maxIdentityLength)
        }

        if let blockedBy = frontmatter.blockedBy {
            switch blockedBy {
            case .manual:
                break
            case .refs(let refs):
                if refs.count > maxBlockedRefsCount {
                    throw TaskValidationError.invalidRange(field: "blocked_by", min: 0, max: maxBlockedRefsCount)
                }
                for ref in refs {
                    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        throw TaskValidationError.invalidFieldValue(field: "blocked_by", value: "blocked reference must not be empty")
                    }
                    if trimmed.count > maxIdentityLength {
                        throw TaskValidationError.fieldTooLong(field: "blocked_by_ref", limit: maxIdentityLength)
                    }
                }
            }
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

        if frontmatter.due == nil, frontmatter.dueTime != nil {
            throw TaskValidationError.invalidFieldValue(field: "due_time", value: "due_time requires due date")
        }
        if frontmatter.persistentReminder == true, (frontmatter.due == nil || frontmatter.dueTime == nil) {
            throw TaskValidationError.invalidFieldValue(
                field: "persistent_reminder",
                value: "persistent_reminder requires due date and due_time"
            )
        }

        if let locationReminder = frontmatter.locationReminder {
            if let name = locationReminder.name,
               name.trimmingCharacters(in: .whitespacesAndNewlines).count > maxLocationNameLength {
                throw TaskValidationError.fieldTooLong(field: "location_name", limit: maxLocationNameLength)
            }

            if !(-90.0...90.0).contains(locationReminder.latitude) {
                throw TaskValidationError.invalidRange(field: "location_latitude", min: -90, max: 90)
            }

            if !(-180.0...180.0).contains(locationReminder.longitude) {
                throw TaskValidationError.invalidRange(field: "location_longitude", min: -180, max: 180)
            }

            if !(50.0...1_000.0).contains(locationReminder.radiusMeters) {
                throw TaskValidationError.invalidRange(field: "location_radius_meters", min: 50, max: 1_000)
            }
        }
    }

    private static func isValidTaskRef(_ ref: String) -> Bool {
        ref.range(of: #"^t-[0-9a-f]{4,6}$"#, options: .regularExpression) != nil
    }
}
