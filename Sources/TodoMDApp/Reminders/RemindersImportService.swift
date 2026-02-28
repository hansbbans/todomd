@preconcurrency import EventKit
import Foundation

protocol RemindersImportServicing: Sendable {
    func fetchLists() async throws -> [ReminderList]
    func fetchIncompleteReminders(calendarID: String?) async throws -> [ReminderImportItem]
    func removeReminders(withIDs reminderIDs: [String]) throws -> ReminderDeletionResult
}

struct ReminderList: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let sourceName: String

    var displayName: String {
        guard !sourceName.isEmpty, sourceName.caseInsensitiveCompare(name) != .orderedSame else {
            return name
        }
        return "\(name) (\(sourceName))"
    }
}

struct ReminderImportItem: Identifiable, Equatable, Sendable {
    let id: String
    let calendarID: String
    let title: String
    let notes: String?
    let dueDateComponents: DateComponents?
    let startDateComponents: DateComponents?
    let priority: Int
    let createdAt: Date?
    let modifiedAt: Date?
}

struct ReminderDeletionResult: Equatable, Sendable {
    let removedCount: Int
    let missingCount: Int
}

enum RemindersImportServiceError: LocalizedError {
    case accessDenied
    case missingUsageDescription
    case listNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access is unavailable. Enable it in iOS Settings for todo.md."
        case .missingUsageDescription:
            return "This build is missing Reminders permission text. Regenerate the Xcode project and rebuild."
        case .listNotFound:
            return "The selected Reminders list no longer exists."
        }
    }
}

final class RemindersImportService: RemindersImportServicing, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func fetchLists() async throws -> [ReminderList] {
        try await ensureAccess()

        return eventStore.calendars(for: .reminder)
            .compactMap { calendar -> ReminderList? in
                guard let calendarID = Self.trimmedText(calendar.calendarIdentifier), !calendarID.isEmpty else {
                    return nil
                }
                let name = Self.trimmedText(calendar.title) ?? "Reminders"
                return ReminderList(
                    id: calendarID,
                    name: name,
                    sourceName: Self.trimmedText(calendar.source?.title) ?? ""
                )
            }
            .sorted(by: Self.listSort)
    }

    func fetchIncompleteReminders(calendarID: String?) async throws -> [ReminderImportItem] {
        try await ensureAccess()

        let selectedCalendarID = Self.trimmedText(calendarID)
        if let selectedCalendarID, eventStore.calendar(withIdentifier: selectedCalendarID) == nil {
            throw RemindersImportServiceError.listNotFound
        }

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        return await ReminderFetchPipeline.fetchIncompleteReminders(
            eventStore: eventStore,
            predicate: predicate,
            selectedCalendarID: selectedCalendarID
        )
    }

    func removeReminders(withIDs reminderIDs: [String]) throws -> ReminderDeletionResult {
        let uniqueIDs = Array(Set(reminderIDs))
        var removed = 0
        var missing = 0

        for reminderID in uniqueIDs {
            guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
                missing += 1
                continue
            }
            guard reminder.calendar?.allowsContentModifications == true else {
                missing += 1
                continue
            }
            try eventStore.remove(reminder, commit: false)
            removed += 1
        }

        if removed > 0 {
            try eventStore.commit()
        }

        return ReminderDeletionResult(removedCount: removed, missingCount: missing)
    }

    private func ensureAccess() async throws {
        let usageDescription = (Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard usageDescription?.isEmpty == false else {
            throw RemindersImportServiceError.missingUsageDescription
        }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await eventStore.requestFullAccessToReminders()
            if granted {
                return
            }
            throw RemindersImportServiceError.accessDenied
        default:
            throw RemindersImportServiceError.accessDenied
        }
    }

    nonisolated private static func listSort(lhs: ReminderList, rhs: ReminderList) -> Bool {
        let lhsSource = lhs.sourceName
        let rhsSource = rhs.sourceName
        if lhsSource.caseInsensitiveCompare(rhsSource) != .orderedSame {
            return lhsSource.localizedCaseInsensitiveCompare(rhsSource) == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated fileprivate static func reminderSort(lhs: ReminderImportItem, rhs: ReminderImportItem) -> Bool {
        let lhsDue = lhs.dueDateComponents?.date
        let rhsDue = rhs.dueDateComponents?.date

        switch (lhsDue, rhsDue) {
        case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    nonisolated private static func trimmedText(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    nonisolated fileprivate static func makeReminderItem(from reminder: EKReminder) -> ReminderImportItem? {
        guard let reminderID = Self.trimmedText(reminder.calendarItemIdentifier), !reminderID.isEmpty else {
            return nil
        }
        guard let calendarID = Self.trimmedText(reminder.calendar?.calendarIdentifier), !calendarID.isEmpty else {
            return nil
        }
        guard let title = Self.trimmedText(reminder.title), !title.isEmpty else {
            return nil
        }
        return ReminderImportItem(
            id: reminderID,
            calendarID: calendarID,
            title: title,
            notes: Self.trimmedText(reminder.notes),
            dueDateComponents: reminder.dueDateComponents,
            startDateComponents: reminder.startDateComponents,
            priority: reminder.priority,
            createdAt: reminder.creationDate,
            modifiedAt: reminder.lastModifiedDate
        )
    }
}

private enum ReminderFetchPipeline {
    static func fetchIncompleteReminders(
        eventStore: EKEventStore,
        predicate: NSPredicate,
        selectedCalendarID: String?
    ) async -> [ReminderImportItem] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let reminderItems = (reminders ?? [])
                    .compactMap(RemindersImportService.makeReminderItem)
                    .filter { item in
                        guard let selectedCalendarID else { return true }
                        return item.calendarID == selectedCalendarID
                    }
                    .sorted(by: RemindersImportService.reminderSort)

                continuation.resume(returning: reminderItems)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

final class FakeRemindersImportService: RemindersImportServicing, @unchecked Sendable {
    private static let defaultListID = "ui-test-reminders-list"
    private static let reminderID = "ui-test-reminder-1"

    private var removedReminderIDs: Set<String> = []

    func fetchLists() async throws -> [ReminderList] {
        [
            ReminderList(
                id: Self.defaultListID,
                name: "UI Test Reminders",
                sourceName: "Local"
            )
        ]
    }

    func fetchIncompleteReminders(calendarID: String?) async throws -> [ReminderImportItem] {
        if let calendarID, calendarID != Self.defaultListID {
            return []
        }

        guard !removedReminderIDs.contains(Self.reminderID) else {
            return []
        }

        return [
            ReminderImportItem(
                id: Self.reminderID,
                calendarID: Self.defaultListID,
                title: "from reminders e2e",
                notes: "created by ui test",
                dueDateComponents: nil,
                startDateComponents: nil,
                priority: 0,
                createdAt: Date(),
                modifiedAt: Date()
            )
        ]
    }

    func removeReminders(withIDs reminderIDs: [String]) throws -> ReminderDeletionResult {
        let unique = Set(reminderIDs)
        let removable = unique.intersection([Self.reminderID])
        removedReminderIDs.formUnion(removable)
        return ReminderDeletionResult(
            removedCount: removable.count,
            missingCount: unique.subtracting(removable).count
        )
    }
}
