import Foundation

public protocol TaskRepository {
    func create(document: TaskDocument, preferredFilename: String?) throws -> TaskRecord
    func update(path: String, mutate: (inout TaskDocument) throws -> Void) throws -> TaskRecord
    func delete(path: String) throws
    func load(path: String) throws -> TaskRecord
    func loadAll() throws -> [TaskRecord]
    func complete(path: String, at completionTime: Date) throws -> TaskRecord
    func completeRepeating(path: String, at completionTime: Date) throws -> (completed: TaskRecord, next: TaskRecord)
}
