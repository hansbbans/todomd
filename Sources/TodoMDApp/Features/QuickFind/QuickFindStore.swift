// Sources/TodoMDApp/Features/QuickFind/QuickFindStore.swift
import Foundation
import Observation

@Observable
@MainActor
final class QuickFindStore {
    private static let recentKey = "quickFind.recentSearches"
    private static let pinnedKey = "quickFind.pinnedSearches"
    private let defaults: UserDefaults

    private(set) var recentSearches: [String]
    private(set) var pinnedSearches: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentSearches = defaults.stringArray(forKey: Self.recentKey) ?? []
        self.pinnedSearches = defaults.stringArray(forKey: Self.pinnedKey) ?? []
    }

    // MARK: - Computed display lists

    var displayedPinned: [String] { pinnedSearches }

    var displayedRecent: [String] {
        let pinnedLowered = Set(pinnedSearches.map { $0.lowercased() })
        return recentSearches
            .filter { !pinnedLowered.contains($0.lowercased()) }
            .prefix(3)
            .map { $0 }
    }

    var isPinFull: Bool { pinnedSearches.count >= 3 }

    // MARK: - Mutations

    func record(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 10 { recentSearches = Array(recentSearches.prefix(10)) }
        persist()
    }

    func pin(_ query: String) {
        guard pinnedSearches.count < 3 else { return }
        guard !pinnedSearches.map({ $0.lowercased() }).contains(query.lowercased()) else { return }
        pinnedSearches.insert(query, at: 0)
        persist()
    }

    func unpin(_ query: String) {
        pinnedSearches.removeAll { $0.lowercased() == query.lowercased() }
        recentSearches.insert(query, at: 0)
        persist()
    }

    func deleteRecent(_ query: String) {
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(recentSearches, forKey: Self.recentKey)
        defaults.set(pinnedSearches, forKey: Self.pinnedKey)
    }
}
