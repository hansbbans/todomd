import XCTest
@testable import TodoMDCore

final class TaskSchemaExporterTests: XCTestCase {
    func testSchemaContainsAllKnownKeys() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])

        XCTAssertEqual(Set(properties.keys), TaskMarkdownCodec.knownKeys)
    }

    func testSchemaStatusEnumMatchesTaskStatus() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        let status = try XCTUnwrap(properties["status"] as? [String: Any])
        let enumValues = try XCTUnwrap(status["enum"] as? [String])

        XCTAssertEqual(Set(enumValues), Set(TaskStatus.allCases.map(\.rawValue)))
    }

    func testSchemaPriorityEnumMatchesTaskPriority() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])
        let priority = try XCTUnwrap(properties["priority"] as? [String: Any])
        let enumValues = try XCTUnwrap(priority["enum"] as? [String])

        XCTAssertEqual(Set(enumValues), Set(TaskPriority.allCases.map(\.rawValue)))
    }

    func testSchemaRequiredFieldsMatchCodec() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        let required = try XCTUnwrap(json["required"] as? [String])

        XCTAssertEqual(Set(required), Set(["title", "status", "created", "source"]))
    }

    func testSchemaIsValidJSONSchemaDocument() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])

        XCTAssertEqual(json["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(json["type"] as? String, "object")
        XCTAssertEqual(json["additionalProperties"] as? Bool, true)
        XCTAssertNotNil(json["properties"])
    }

    func testSchemaIncludesValidationRangesAndLengths() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: Any])

        let title = try XCTUnwrap(properties["title"] as? [String: Any])
        XCTAssertEqual(title["maxLength"] as? Int, TaskValidation.maxTitleLength)

        let description = try XCTUnwrap(properties["description"] as? [String: Any])
        XCTAssertEqual(description["maxLength"] as? Int, TaskValidation.maxDescriptionLength)

        let estimatedMinutes = try XCTUnwrap(properties["estimated_minutes"] as? [String: Any])
        XCTAssertEqual(estimatedMinutes["minimum"] as? Int, 0)
        XCTAssertEqual(estimatedMinutes["maximum"] as? Int, 100_000)

        let latitude = try XCTUnwrap(properties["location_latitude"] as? [String: Any])
        XCTAssertEqual(latitude["minimum"] as? Int, -90)
        XCTAssertEqual(latitude["maximum"] as? Int, 90)

        let longitude = try XCTUnwrap(properties["location_longitude"] as? [String: Any])
        XCTAssertEqual(longitude["minimum"] as? Int, -180)
        XCTAssertEqual(longitude["maximum"] as? Int, 180)

        let radius = try XCTUnwrap(properties["location_radius_meters"] as? [String: Any])
        XCTAssertEqual(radius["minimum"] as? Int, 50)
        XCTAssertEqual(radius["maximum"] as? Int, 1_000)
    }

    func testSchemaIncludesCrossFieldDependencies() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: schema) as? [String: Any])
        let allOf = try XCTUnwrap(json["allOf"] as? [[String: Any]])

        XCTAssertTrue(hasDependency(in: allOf, ifRequired: ["due_time"], thenRequired: ["due"]))
        XCTAssertTrue(hasDependency(in: allOf, ifRequired: ["scheduled_time"], thenRequired: ["scheduled"]))
        XCTAssertTrue(hasConstDependency(
            in: allOf,
            field: "persistent_reminder",
            const: true,
            thenRequired: ["due", "due_time"]
        ))
        XCTAssertTrue(hasAnyOfDependency(
            in: allOf,
            triggeringFields: ["location_name", "location_radius_meters", "location_trigger"],
            thenRequired: ["location_latitude", "location_longitude"]
        ))
    }

    private func hasDependency(
        in allOf: [[String: Any]],
        ifRequired: [String],
        thenRequired: [String]
    ) -> Bool {
        allOf.contains { entry in
            let condition = entry["if"] as? [String: Any]
            let required = condition?["required"] as? [String]
            let then = entry["then"] as? [String: Any]
            let thenFields = then?["required"] as? [String]
            return required == ifRequired && Set(thenFields ?? []) == Set(thenRequired)
        }
    }

    private func hasConstDependency(
        in allOf: [[String: Any]],
        field: String,
        const: Bool,
        thenRequired: [String]
    ) -> Bool {
        allOf.contains { entry in
            let condition = entry["if"] as? [String: Any]
            let required = condition?["required"] as? [String]
            let properties = condition?["properties"] as? [String: Any]
            let property = properties?[field] as? [String: Any]
            let then = entry["then"] as? [String: Any]
            let thenFields = then?["required"] as? [String]

            return required == [field]
                && property?["const"] as? Bool == const
                && Set(thenFields ?? []) == Set(thenRequired)
        }
    }

    private func hasAnyOfDependency(
        in allOf: [[String: Any]],
        triggeringFields: [String],
        thenRequired: [String]
    ) -> Bool {
        allOf.contains { entry in
            let condition = entry["if"] as? [String: Any]
            let anyOf = condition?["anyOf"] as? [[String: Any]]
            let triggeredFields = Set(anyOf?.compactMap { ($0["required"] as? [String])?.first } ?? [])
            let then = entry["then"] as? [String: Any]
            let thenFields = then?["required"] as? [String]

            return triggeredFields.isSuperset(of: Set(triggeringFields)) && Set(thenFields ?? []) == Set(thenRequired)
        }
    }
}
