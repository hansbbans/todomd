import Foundation

public final class FileTaskRepository: TaskRepository {
    private let rootURL: URL
    private let fileIO: TaskFileIO
    private let codec: TaskMarkdownCodec
    private let filenameGenerator: TaskFilenameGenerator
    private let lifecycleService: TaskLifecycleService
    private let refGenerator: TaskRefGenerator
    private var knownRefsCache: Set<String>?

    public init(
        rootURL: URL,
        fileIO: TaskFileIO = TaskFileIO(),
        codec: TaskMarkdownCodec = TaskMarkdownCodec(),
        filenameGenerator: TaskFilenameGenerator = TaskFilenameGenerator(),
        lifecycleService: TaskLifecycleService = TaskLifecycleService(),
        refGenerator: TaskRefGenerator = TaskRefGenerator()
    ) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.fileIO = fileIO
        self.codec = codec
        self.filenameGenerator = filenameGenerator
        self.lifecycleService = lifecycleService
        self.refGenerator = refGenerator
        self.knownRefsCache = nil
    }

    public func create(document: TaskDocument, preferredFilename: String?) throws -> TaskRecord {
        var document = document
        document = try ensureReference(onCreate: document)
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
        let fallbackTitle = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let document = try codec.parse(markdown: raw, fallbackTitle: fallbackTitle)
        return TaskRecord(identity: TaskFileIdentity(path: path), document: document)
    }

    public func loadAll() throws -> [TaskRecord] {
        let urls = try fileIO.enumerateMarkdownFiles(rootURL: rootURL)
        return try urls.map { url in
            let raw = try fileIO.read(path: url.path)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let document = try codec.parse(markdown: raw, fallbackTitle: fallbackTitle)
            return TaskRecord(identity: TaskFileIdentity(path: url.path), document: document)
        }
    }

    public func complete(path: String, at completionTime: Date, completedBy: String? = "user") throws -> TaskRecord {
        try update(path: path) { document in
            document = lifecycleService.markComplete(document, at: completionTime, completedBy: completedBy)
        }
    }

    public func completeRepeating(
        path: String,
        at completionTime: Date,
        completedBy: String? = "user"
    ) throws -> (completed: TaskRecord, next: TaskRecord) {
        let existing = try load(path: path)
        let (completedDocument, nextDocument) = try lifecycleService.completeRepeating(
            existing.document,
            at: completionTime,
            completedBy: completedBy
        )

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

    private func ensureReference(onCreate document: TaskDocument) throws -> TaskDocument {
        var copy = document
        let existingRefs = try knownTaskRefs()

        if let existingRef = copy.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
           TaskRefGenerator.isValid(ref: existingRef),
           !existingRefs.contains(existingRef) {
            copy.frontmatter.ref = existingRef
            knownRefsCache?.insert(existingRef)
            return copy
        }

        let generated = refGenerator.generate(existingRefs: existingRefs)
        copy.frontmatter.ref = generated
        knownRefsCache?.insert(generated)
        return copy
    }

    private func knownTaskRefs() throws -> Set<String> {
        if let knownRefsCache {
            return knownRefsCache
        }

        let urls = try fileIO.enumerateMarkdownFiles(rootURL: rootURL)
        var refs: Set<String> = []
        refs.reserveCapacity(urls.count)
        for url in urls {
            let raw = try fileIO.read(path: url.path)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            guard let document = try? codec.parse(markdown: raw, fallbackTitle: fallbackTitle) else {
                continue
            }
            guard let ref = document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
                  TaskRefGenerator.isValid(ref: ref) else {
                continue
            }
            refs.insert(ref)
        }
        knownRefsCache = refs
        return refs
    }
}
