// Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift
import Foundation
import Observation

// MARK: - RecentItem

struct RecentItem: Codable, Hashable {

    // MARK: Destination

    enum Destination: Hashable {
        case view(String)   // ViewIdentifier.rawValue, e.g. "project:Italy", "inbox", "tag:work"
        case task(String)   // task file path
    }

    var label: String       // display text shown in the row
    var icon: String        // SF Symbol name; always non-empty
    var tintHex: String?    // nil = .primary via AppIconGlyph; strips # in color(forHex:)
    var destination: Destination
}

// MARK: - RecentItem.Destination: Codable

extension RecentItem.Destination: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch type {
        case "view": self = .view(value)
        case "task": self = .task(value)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unknown destination type: \(type)")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .view(let v):
            try c.encode("view", forKey: .type)
            try c.encode(v, forKey: .value)
        case .task(let v):
            try c.encode("task", forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }
}

// MARK: - QuickFindStore

@Observable
@MainActor
final class QuickFindStore {
    private static let recentKey = "quickFind.recentSearches"
    private static let pinnedKey = "quickFind.pinnedSearches"
    private static let recordTasksKey = "quickFind.recordTasks"
    private let defaults: UserDefaults

    private(set) var recentSearches: [RecentItem]
    private(set) var pinnedSearches: [RecentItem]
    var recordTasks: Bool {
        didSet { defaults.set(recordTasks, forKey: Self.recordTasksKey) }
    }

    init(defaults: UserDefaults = TaskFolderPreferences.shared, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        let legacyDefaults = legacyDefaults ?? Self.defaultLegacyDefaults(for: defaults)

        let recentSearches = Self.load([RecentItem].self, key: Self.recentKey, from: defaults, fallback: legacyDefaults)
        let pinnedSearches = Self.load([RecentItem].self, key: Self.pinnedKey, from: defaults, fallback: legacyDefaults)
        let recordTasks = Self.loadBool(key: Self.recordTasksKey, from: defaults, fallback: legacyDefaults) ?? true

        self.recentSearches = recentSearches.value
        self.pinnedSearches = pinnedSearches.value
        self.recordTasks = recordTasks

        if recentSearches.didMigrate || pinnedSearches.didMigrate {
            persist()
        }
        if defaults.object(forKey: Self.recordTasksKey) == nil,
           let legacyDefaults,
           legacyDefaults.object(forKey: Self.recordTasksKey) != nil {
            defaults.set(recordTasks, forKey: Self.recordTasksKey)
        }
    }

    // MARK: - Computed display lists

    var displayedPinned: [RecentItem] { pinnedSearches }

    var displayedRecent: [RecentItem] {
        let pinnedDestinations = Set(pinnedSearches.map(\.destination))
        return recentSearches
            .filter { !pinnedDestinations.contains($0.destination) }
            .prefix(3)
            .map { $0 }
    }

    var isPinFull: Bool { pinnedSearches.count >= 5 }

    // MARK: - Mutations

    func record(item: RecentItem) {
        guard !item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if case .task = item.destination, !recordTasks { return }
        guard !pinnedSearches.contains(where: { $0.destination == item.destination }) else { return }
        recentSearches.removeAll { $0.destination == item.destination }
        recentSearches.insert(item, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        persist()
    }

    func pin(_ item: RecentItem) {
        guard pinnedSearches.count < 5 else { return }
        guard !pinnedSearches.contains(where: { $0.destination == item.destination }) else { return }
        pinnedSearches.insert(item, at: 0)
        persist()
    }

    func unpin(_ item: RecentItem) {
        pinnedSearches.removeAll { $0.destination == item.destination }
        recentSearches.removeAll { $0.destination == item.destination }
        recentSearches.insert(item, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        persist()
    }

    func deleteRecent(_ item: RecentItem) {
        recentSearches.removeAll { $0.destination == item.destination }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(try? JSONEncoder().encode(recentSearches), forKey: Self.recentKey)
        defaults.set(try? JSONEncoder().encode(pinnedSearches), forKey: Self.pinnedKey)
    }

    private static func defaultLegacyDefaults(for defaults: UserDefaults) -> UserDefaults? {
        defaults === UserDefaults.standard ? nil : .standard
    }

    private static func load<T: Decodable>(
        _: T.Type,
        key: String,
        from defaults: UserDefaults,
        fallback legacyDefaults: UserDefaults?
    ) -> (value: T, didMigrate: Bool) where T: ExpressibleByArrayLiteral {
        if let decoded = decode(T.self, key: key, from: defaults) {
            return (decoded, false)
        }
        if let legacyDefaults, let decoded = decode(T.self, key: key, from: legacyDefaults) {
            return (decoded, true)
        }
        return ([], false)
    }

    private static func loadBool(key: String, from defaults: UserDefaults, fallback legacyDefaults: UserDefaults?) -> Bool? {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        return legacyDefaults?.object(forKey: key) as? Bool
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

}
