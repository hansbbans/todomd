import Foundation

public struct TaskLifecycleService {
    public var recurrenceService: RecurrenceService

    public init(recurrenceService: RecurrenceService = RecurrenceService()) {
        self.recurrenceService = recurrenceService
    }

    public func markComplete(_ document: TaskDocument, at completionTime: Date) -> TaskDocument {
        var copy = document
        copy.frontmatter.status = .done
        copy.frontmatter.completed = completionTime
        copy.frontmatter.modified = completionTime
        return copy
    }

    public func completeRepeating(_ document: TaskDocument, at completionTime: Date) throws -> (completed: TaskDocument, next: TaskDocument) {
        guard let recurrence = document.frontmatter.recurrence else {
            throw TaskError.recurrenceFailure("Task has no recurrence rule")
        }

        var completed = markComplete(document, at: completionTime)
        completed.frontmatter.recurrence = nil

        var next = document
        next.frontmatter.status = .todo
        next.frontmatter.created = completionTime
        next.frontmatter.modified = completionTime
        next.frontmatter.completed = nil

        if let due = document.frontmatter.due {
            next.frontmatter.due = try recurrenceService.nextOccurrence(after: due, rule: recurrence)
        }

        if let deferDate = document.frontmatter.defer {
            next.frontmatter.defer = try recurrenceService.nextOccurrence(after: deferDate, rule: recurrence)
        }

        if let scheduled = document.frontmatter.scheduled {
            next.frontmatter.scheduled = try recurrenceService.nextOccurrence(after: scheduled, rule: recurrence)
        }

        next.frontmatter.recurrence = recurrence
        return (completed, next)
    }
}
