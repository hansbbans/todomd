import Foundation
#if canImport(SwiftData)
import SwiftData

@Model
public final class TaskIndexRecord {
    @Attribute(.unique) public var path: String
    public var filename: String
    public var title: String
    public var subtitle: String?
    public var status: String
    public var dueISODate: String?
    public var dueTime: String?
    public var deferISODate: String?
    public var scheduledISODate: String?
    public var priority: String
    public var flagged: Bool
    public var area: String?
    public var project: String?
    public var tags: [String]
    public var recurrence: String?
    public var estimatedMinutes: Int?
    public var source: String
    public var modifiedAt: Date?
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        path: String,
        filename: String,
        title: String,
        subtitle: String?,
        status: String,
        dueISODate: String?,
        dueTime: String?,
        deferISODate: String?,
        scheduledISODate: String?,
        priority: String,
        flagged: Bool,
        area: String?,
        project: String?,
        tags: [String],
        recurrence: String?,
        estimatedMinutes: Int?,
        source: String,
        modifiedAt: Date?,
        completedAt: Date?,
        createdAt: Date
    ) {
        self.path = path
        self.filename = filename
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.dueISODate = dueISODate
        self.dueTime = dueTime
        self.deferISODate = deferISODate
        self.scheduledISODate = scheduledISODate
        self.priority = priority
        self.flagged = flagged
        self.area = area
        self.project = project
        self.tags = tags
        self.recurrence = recurrence
        self.estimatedMinutes = estimatedMinutes
        self.source = source
        self.modifiedAt = modifiedAt
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}
#endif
