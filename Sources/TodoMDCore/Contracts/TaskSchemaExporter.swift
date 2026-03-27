import Foundation

public enum TaskSchemaExporter {
    public static func exportJSONSchema() -> Data {
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://todomd.app/schema/task-v1.json",
            "title": "todo.md Task",
            "description": "Frontmatter schema for todo.md task files.",
            "type": "object",
            "required": ["title", "status", "created", "source"],
            "additionalProperties": true,
            "properties": properties(),
            "allOf": dependencyRules()
        ]

        return try! JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
    }

    private static func properties() -> [String: Any] {
        var properties: [String: Any] = [:]
        properties.reserveCapacity(TaskMarkdownCodec.knownKeys.count)

        for key in TaskMarkdownCodec.knownKeys {
            properties[key] = schema(for: key)
        }

        return properties
    }

    private static func schema(for key: String) -> [String: Any] {
        switch key {
        case "ref":
            return [
                "type": "string",
                "pattern": "^t-[0-9a-f]{4,6}$",
                "maxLength": TaskValidation.maxIdentityLength
            ]
        case "title":
            return ["type": "string", "maxLength": TaskValidation.maxTitleLength]
        case "description":
            return ["type": "string", "maxLength": TaskValidation.maxDescriptionLength]
        case "location_name":
            return ["type": "string", "maxLength": TaskValidation.maxLocationNameLength]
        case "assignee", "completed_by":
            return ["type": "string", "maxLength": TaskValidation.maxIdentityLength]
        case "source":
            return ["type": "string", "minLength": 1]
        case "area", "project", "recurrence", "url":
            return ["type": "string"]
        case "status":
            return ["type": "string", "enum": TaskStatus.allCases.map(\.rawValue)]
        case "priority":
            return ["type": "string", "enum": TaskPriority.allCases.map(\.rawValue)]
        case "due", "defer", "scheduled":
            return ["type": "string", "format": "date"]
        case "due_time", "scheduled_time":
            return ["type": "string", "pattern": #"^\d{2}:\d{2}$"#]
        case "persistent_reminder", "flagged":
            return ["type": "boolean"]
        case "tags":
            return [
                "type": "array",
                "maxItems": TaskValidation.maxTagsCount,
                "items": ["type": "string", "maxLength": TaskValidation.maxTagLength]
            ]
        case "estimated_minutes":
            return ["type": "integer", "minimum": 0, "maximum": 100_000]
        case "location_latitude":
            return ["type": "number", "minimum": -90, "maximum": 90]
        case "location_longitude":
            return ["type": "number", "minimum": -180, "maximum": 180]
        case "location_radius_meters":
            return ["type": "number", "minimum": 50, "maximum": 1_000]
        case "location_trigger":
            return ["type": "string", "enum": TaskLocationReminderTrigger.allCases.map(\.rawValue)]
        case "created", "modified", "completed":
            return ["type": "string", "format": "date-time"]
        case "blocked_by":
            return [
                "anyOf": [
                    ["type": "boolean"],
                    ["type": "string", "minLength": 1, "maxLength": TaskValidation.maxIdentityLength],
                    [
                        "type": "array",
                        "maxItems": TaskValidation.maxBlockedRefsCount,
                        "items": [
                            "type": "string",
                            "minLength": 1,
                            "maxLength": TaskValidation.maxIdentityLength
                        ]
                    ]
                ]
            ]
        default:
            return ["type": "string"]
        }
    }

    private static func dependencyRules() -> [[String: Any]] {
        [
            [
                "if": ["required": ["due_time"]],
                "then": ["required": ["due"]]
            ],
            [
                "if": ["required": ["scheduled_time"]],
                "then": ["required": ["scheduled"]]
            ],
            [
                "if": [
                    "required": ["persistent_reminder"],
                    "properties": [
                        "persistent_reminder": ["const": true]
                    ]
                ],
                "then": ["required": ["due", "due_time"]]
            ],
            [
                "if": [
                    "anyOf": [
                        ["required": ["location_name"]],
                        ["required": ["location_latitude"]],
                        ["required": ["location_longitude"]],
                        ["required": ["location_radius_meters"]],
                        ["required": ["location_trigger"]]
                    ]
                ],
                "then": ["required": ["location_latitude", "location_longitude"]]
            ]
        ]
    }
}
