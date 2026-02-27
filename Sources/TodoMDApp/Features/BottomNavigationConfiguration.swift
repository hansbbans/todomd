import Foundation

struct BottomNavigationSection: Codable, Identifiable, Equatable {
    var id: String
    var viewRawValue: String

    init(id: String = UUID().uuidString, view: ViewIdentifier) {
        self.id = id
        self.viewRawValue = view.rawValue
    }

    var viewIdentifier: ViewIdentifier {
        ViewIdentifier(rawValue: viewRawValue)
    }
}

enum BottomNavigationSettings {
    static let sectionsKey = "settings_bottom_navigation_sections_v1"
    static let maxSections = 5

    static let defaultSections: [BottomNavigationSection] = [
        BottomNavigationSection(view: .builtIn(.inbox)),
        BottomNavigationSection(view: .builtIn(.today)),
        BottomNavigationSection(view: .builtIn(.upcoming))
    ]

    static var defaultSectionsRawValue: String {
        encodeSections(defaultSections)
    }

    static func decodeSections(_ rawValue: String) -> [BottomNavigationSection] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }

        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BottomNavigationSection].self, from: data) else {
            return defaultSections
        }

        let filtered = decoded.filter { section in
            !section.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !section.viewRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return Array(filtered.prefix(maxSections))
    }

    static func encodeSections(_ sections: [BottomNavigationSection]) -> String {
        let limited = Array(sections.prefix(maxSections))
        guard let data = try? JSONEncoder().encode(limited),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }
}
