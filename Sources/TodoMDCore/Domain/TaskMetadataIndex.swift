// TaskMetadataIndex.swift
// Lightweight in-memory index for fast perspective query evaluation.
// Maps task ref/path → pre-computed field values for frequently-queried fields.
//
// Design intent:
// • Build the index once from the full set of TaskRecords after a sync.
// • Use `paths(matching:)` as a cheap pre-filter before loading/evaluating
//   the full TaskRecord in PerspectiveQueryEngine.
// • Keep the index current with incremental `update` / `remove` calls on
//   every mutation so callers never need a full rebuild mid-session.

import Foundation

// MARK: - TaskMetadataEntry

/// Pre-computed, cheaply-comparable metadata derived from a single TaskRecord.
/// All date values are stored as ISO-8601 strings for lexicographic comparison.
public struct TaskMetadataEntry: Sendable {

    // MARK: Identity

    /// Absolute file-system path — the primary key of the index.
    public let path: String

    /// Short task reference (e.g. `t-1a2b`), when present.
    public let ref: String?

    // MARK: Frequently-filtered fields

    /// Raw `TaskStatus` value (e.g. `"todo"`, `"in-progress"`, `"done"`).
    public let status: String

    /// Raw `TaskPriority` value (e.g. `"none"`, `"low"`, `"medium"`, `"high"`).
    public let priority: String

    /// Area label, if set.
    public let area: String?

    /// Project label, if set.
    public let project: String?

    /// Normalised, lowercased tag list.
    public let tags: [String]

    /// Whether a due date is present.
    public let hasDue: Bool

    /// ISO-8601 representation of the due date (e.g. `"2026-03-15"`), if set.
    /// Stored as a string so comparisons can be done lexicographically without
    /// constructing `LocalDate` values.
    public let dueDate: String?

    /// Whether the task is flagged.
    public let flagged: Bool

    /// Assignee handle, if set.
    public let assignee: String?

    /// Source identifier (e.g. the folder name or integration origin).
    public let source: String

    /// Whether the task has a recurrence rule defined.
    public let hasRecurrence: Bool

    /// Whether the task has a location-based reminder attached.
    public let hasLocationReminder: Bool

    // MARK: - Field matching

    /// Evaluates a simple field comparison against this entry without requiring the full TaskRecord.
    ///
    /// Returns `true` when the entry's value satisfies `field op value`, `false` when it does not,
    /// and `nil` when the field is not indexed here (caller must fall back to full evaluation).
    ///
    /// - Parameters:
    ///   - field: The `PerspectiveField` to evaluate.
    ///   - op:    The `PerspectiveOperator` that defines how to compare.
    ///   - value: The rule's string value (may be a comma-separated list for `in`/`containsAny`).
    public func matches(field: PerspectiveField, operator op: PerspectiveOperator, value: String) -> Bool? {
        switch field {
        case .status:
            return matchString(status, operator: op, ruleValue: value)

        case .priority:
            return matchString(priority, operator: op, ruleValue: value)

        case .flagged:
            return matchBool(flagged, operator: op, ruleValue: value)

        case .area:
            return matchOptionalString(area, operator: op, ruleValue: value)

        case .project:
            return matchOptionalString(project, operator: op, ruleValue: value)

        case .source:
            return matchString(source, operator: op, ruleValue: value)

        case .ref:
            return matchOptionalString(ref, operator: op, ruleValue: value)

        case .assignee:
            return matchOptionalString(assignee, operator: op, ruleValue: value)

        case .tags:
            return matchTags(tags, operator: op, ruleValue: value)

        case .due:
            return matchDatePresence(hasDue: hasDue, isoDate: dueDate, operator: op, ruleValue: value)

        case .recurrence:
            return matchPresenceOnly(hasRecurrence, operator: op)

        default:
            // Fields not represented in the index (body, created, modified, etc.)
            // require full TaskRecord evaluation — signal that to the caller.
            return nil
        }
    }

    // MARK: - Internal comparison helpers

    private func matchString(_ lhs: String, operator op: PerspectiveOperator, ruleValue: String) -> Bool? {
        let lhsNorm = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhsValues = splitValues(ruleValue)
        let first = rhsValues.first ?? ""

        switch op {
        case .equals:
            return !first.isEmpty && lhsNorm == first
        case .notEquals:
            return !first.isEmpty && lhsNorm != first
        case .in:
            let set = Set(rhsValues)
            return !set.isEmpty && set.contains(lhsNorm)
        case .contains, .stringContains:
            return !first.isEmpty && lhsNorm.localizedStandardContains(first)
        case .isSet, .isNotNil:
            return !lhsNorm.isEmpty
        case .isNotSet, .isNil:
            return lhsNorm.isEmpty
        default:
            return nil
        }
    }

    private func matchOptionalString(_ lhs: String?, operator op: PerspectiveOperator, ruleValue: String) -> Bool? {
        let trimmed = lhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch op {
        case .isSet, .isNotNil:
            return !(trimmed?.isEmpty ?? true)
        case .isNotSet, .isNil:
            return trimmed?.isEmpty ?? true
        default:
            return matchString(trimmed ?? "", operator: op, ruleValue: ruleValue)
        }
    }

    private func matchBool(_ lhs: Bool, operator op: PerspectiveOperator, ruleValue: String) -> Bool? {
        switch op {
        case .isTrue:
            return lhs
        case .isFalse:
            return !lhs
        case .equals:
            guard let rhsBool = coerceBool(ruleValue) else { return nil }
            return lhs == rhsBool
        case .notEquals:
            guard let rhsBool = coerceBool(ruleValue) else { return nil }
            return lhs != rhsBool
        default:
            return nil
        }
    }

    private func matchTags(_ lhs: [String], operator op: PerspectiveOperator, ruleValue: String) -> Bool? {
        let rhsValues = splitValues(ruleValue)
        let first = rhsValues.first ?? ""

        switch op {
        case .equals:
            return !first.isEmpty && lhs.contains(first)
        case .contains, .stringContains:
            return !first.isEmpty && lhs.contains(where: { $0.contains(first) })
        case .containsAny, .in:
            let probes = Set(rhsValues)
            return !probes.isEmpty && lhs.contains { probes.contains($0) }
        case .containsAll:
            let probes = Set(rhsValues)
            return !probes.isEmpty && probes.isSubset(of: Set(lhs))
        case .isSet, .isNotNil:
            return !lhs.isEmpty
        case .isNotSet, .isNil:
            return lhs.isEmpty
        default:
            return nil
        }
    }

    /// Matches `due` field: handles nil-check operators and simple string comparisons
    /// using lexicographic ordering of ISO-8601 date strings.
    private func matchDatePresence(
        hasDue: Bool,
        isoDate: String?,
        operator op: PerspectiveOperator,
        ruleValue: String
    ) -> Bool? {
        switch op {
        case .isSet, .isNotNil:
            return hasDue
        case .isNotSet, .isNil:
            return !hasDue
        case .equals, .on:
            guard let isoDate else { return false }
            return isoDate == ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .before:
            guard let isoDate else { return false }
            let probe = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return !probe.isEmpty && isoDate < probe
        case .after:
            guard let isoDate else { return false }
            let probe = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return !probe.isEmpty && isoDate > probe
        case .onOrBefore:
            guard let isoDate else { return false }
            let probe = ruleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return !probe.isEmpty && isoDate <= probe
        default:
            // Complex relative date operators (beforeToday, afterToday, inNext, inPast, between)
            // require full LocalDate arithmetic — signal the caller to fall back.
            return nil
        }
    }

    /// For boolean-presence-only fields (e.g. `recurrence`), only nil/set operators are indexed.
    private func matchPresenceOnly(_ hasValue: Bool, operator op: PerspectiveOperator) -> Bool? {
        switch op {
        case .isSet, .isNotNil:
            return hasValue
        case .isNotSet, .isNil:
            return !hasValue
        default:
            return nil
        }
    }

    // MARK: - Value coercion helpers

    /// Splits a comma-separated rule value into trimmed, lowercased tokens.
    private func splitValues(_ raw: String) -> [String] {
        if raw.contains(",") {
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? [] : [trimmed]
    }

    private func coerceBool(_ raw: String) -> Bool? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["1", "true", "yes", "flagged", "on"].contains(normalized) { return true }
        if ["0", "false", "no", "off"].contains(normalized) { return false }
        return nil
    }
}

// MARK: - TaskMetadataIndex

/// Thread-safe in-memory index of `TaskMetadataEntry` values keyed by file path.
///
/// The index is built from a full array of `TaskRecord`s and can be incrementally
/// updated as individual records are mutated or deleted.
public final class TaskMetadataIndex: @unchecked Sendable {

    // MARK: - Private state

    private var entriesByPath: [String: TaskMetadataEntry]
    private let lock = NSLock()

    // MARK: - Initialisation

    private init(entriesByPath: [String: TaskMetadataEntry]) {
        self.entriesByPath = entriesByPath
    }

    // MARK: - Factory

    /// Builds a new index from the given records. O(n) in the number of records.
    public static func build(from records: [TaskRecord]) -> TaskMetadataIndex {
        var map: [String: TaskMetadataEntry] = [:]
        map.reserveCapacity(records.count)
        for record in records {
            let entry = TaskMetadataEntry(from: record)
            map[entry.path] = entry
        }
        return TaskMetadataIndex(entriesByPath: map)
    }

    // MARK: - Incremental updates

    /// Incrementally updates the index for a single mutated record.
    public func update(record: TaskRecord) {
        let entry = TaskMetadataEntry(from: record)
        lock.lock()
        entriesByPath[entry.path] = entry
        lock.unlock()
    }

    /// Removes the entry for `path` when a task file is deleted.
    public func remove(path: String) {
        lock.lock()
        entriesByPath.removeValue(forKey: path)
        lock.unlock()
    }

    // MARK: - Reads

    /// Returns the entry for the given path, or `nil` if not indexed.
    public func entry(for path: String) -> TaskMetadataEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entriesByPath[path]
    }

    /// Returns all indexed entries (order is unspecified).
    public func allEntries() -> [TaskMetadataEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entriesByPath.values)
    }

    /// Returns the paths of all entries that satisfy `predicate`.
    ///
    /// Use this as a cheap pre-filter before loading full `TaskRecord`s from disk:
    ///
    /// ```swift
    /// let candidates = index.paths(matching: { $0.status == "todo" })
    /// // load only the candidate records and run full evaluation
    /// ```
    public func paths(matching predicate: (TaskMetadataEntry) -> Bool) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entriesByPath.values.filter(predicate).map(\.path)
    }
}

// MARK: - TaskMetadataEntry convenience initialiser

extension TaskMetadataEntry {
    /// Extracts index-relevant fields from a `TaskRecord`.
    init(from record: TaskRecord) {
        let fm = record.document.frontmatter
        self.path = record.identity.path
        self.ref = fm.ref?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty()
        self.status = fm.status.rawValue
        self.priority = fm.priority.rawValue
        self.area = fm.area?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        self.project = fm.project?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        self.tags = fm.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        self.hasDue = fm.due != nil
        self.dueDate = fm.due?.isoString
        self.flagged = fm.flagged
        self.assignee = fm.assignee?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty()
        self.source = fm.source
        self.hasRecurrence = fm.recurrence != nil && !(fm.recurrence?.isEmpty ?? true)
        self.hasLocationReminder = fm.locationReminder != nil
    }
}

// MARK: - String helper

private extension String {
    /// Returns `nil` when the string is empty, otherwise returns `self`.
    func nilIfEmpty() -> String? {
        isEmpty ? nil : self
    }
}
