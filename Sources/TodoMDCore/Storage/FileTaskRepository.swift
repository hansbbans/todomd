import Foundation

public final class FileTaskRepository: TaskRepository {
    private let rootURL: URL
    private let fileIO: TaskFileIO
    private let codec: TaskMarkdownCodec
    private let filenameGenerator: TaskFilenameGenerator
    private let lifecycleService: TaskLifecycleService

    public init(
        rootURL: URL,
        fileIO: TaskFileIO = TaskFileIO(),
        codec: TaskMarkdownCodec = TaskMarkdownCodec(),
        filenameGenerator: TaskFilenameGenerator = TaskFilenameGenerator(),
        lifecycleService: TaskLifecycleService = TaskLifecycleService()
    ) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.fileIO = fileIO
        self.codec = codec
        self.filenameGenerator = filenameGenerator
        self.lifecycleService = lifecycleService
    }

    public func create(document: TaskDocument, preferredFilename: String?) throws -> TaskRecord {
        try TaskValidation.validate(document: document)

        let existing = Set(try fileIO.enumerateMarkdownFiles(rootURL: rootURL).map(\.lastPathComponent))
        let filename = sanitizeFilename(preferredFilename) ?? filenameGenerator.generate(title: document.frontmatter.title, existingFilenames: existing)
        let path = rootURL.appendingPathComponent(filename).path

        let content = try codec.serialize(document: document)
        try fileIO.write(path: path, content: content)

        return TaskRecord(identity: TaskFileIdentity(path: path), document: document)
    }

    public func update(path: String, mutate: (inout TaskDocument) throws -> Void) throws -> TaskRecord {
        var record = try load(path: path)
        try mutate(&record.document)
        record.document.frontmatter.modified = Date()
        try TaskValidation.validate(document: record.document)
        let serialized = try codec.serialize(document: record.document)
        try fileIO.write(path: path, content: serialized)
        return record
    }

    public func delete(path: String) throws {
        try fileIO.delete(path: path)
    }

    public func load(path: String) throws -> TaskRecord {
        let raw = try fileIO.read(path: path)
        let document = try codec.parse(markdown: raw)
        return TaskRecord(identity: TaskFileIdentity(path: path), document: document)
    }

    public func loadAll() throws -> [TaskRecord] {
        let urls = try fileIO.enumerateMarkdownFiles(rootURL: rootURL)
        return try urls.map { url in
            let raw = try fileIO.read(path: url.path)
            let document = try codec.parse(markdown: raw)
            return TaskRecord(identity: TaskFileIdentity(path: url.path), document: document)
        }
    }

    public func complete(path: String, at completionTime: Date) throws -> TaskRecord {
        try update(path: path) { document in
            document = lifecycleService.markComplete(document, at: completionTime)
        }
    }

    public func completeRepeating(path: String, at completionTime: Date) throws -> (completed: TaskRecord, next: TaskRecord) {
        let existing = try load(path: path)
        let (completedDocument, nextDocument) = try lifecycleService.completeRepeating(existing.document, at: completionTime)

        let completedSerialized = try codec.serialize(document: completedDocument)
        try fileIO.write(path: path, content: completedSerialized)
        let completedRecord = TaskRecord(identity: TaskFileIdentity(path: path), document: completedDocument)

        let nextRecord = try create(document: nextDocument, preferredFilename: nil)
        return (completedRecord, nextRecord)
    }

    private func sanitizeFilename(_ preferred: String?) -> String? {
        guard let preferred else { return nil }
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasSuffix(".md") ? trimmed : "\(trimmed).md"
    }
}
