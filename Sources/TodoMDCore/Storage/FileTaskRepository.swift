import Foundation

public final class FileTaskRepository: TaskRepository, @unchecked Sendable {
    private let rootURL: URL
    private let fileIO: TaskFileIO
    private let codec: TaskMarkdownCodec
    private let filenameGenerator: TaskFilenameGenerator
    private let lifecycleService: TaskLifecycleService
    private let refGenerator: TaskRefGenerator
    private var knownRefsCache: Set<String>?
    private var knownFilenamesCache: Set<String>?

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
        self.knownFilenamesCache = nil
    }

    public func create(document: TaskDocument, preferredFilename: String?) throws -> TaskRecord {
        var document = document
        document = try ensureReference(onCreate: document)
        try TaskValidation.validate(document: document)

        let existing = try knownMarkdownFilenames()
        let filename = sanitizeFilename(preferredFilename) ?? filenameGenerator.generate(title: document.frontmatter.title, existingFilenames: existing)
        let path = rootURL.appendingPathComponent(filename).path

        let content = try codec.serialize(document: document)
        try fileIO.write(path: path, content: content)
        knownFilenamesCache?.insert(filename)

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
        knownFilenamesCache?.remove(URL(fileURLWithPath: path).lastPathComponent)
    }

    public func load(path: String) throws -> TaskRecord {
        let raw = try fileIO.read(path: path)
        let fallbackTitle = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let document = try codec.parse(markdown: raw, fallbackTitle: fallbackTitle)
        return TaskRecord(identity: TaskFileIdentity(path: path), document: document)
    }

    public func loadAll() throws -> [TaskRecord] {
        let urls = try fileIO.enumerateMarkdownFiles(rootURL: rootURL)
        return try loadRecords(at: urls)
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
        for record in try loadRecords(at: urls, skipInvalid: true) {
            let document = record.document
            guard let ref = document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
                  TaskRefGenerator.isValid(ref: ref) else {
                continue
            }
            refs.insert(ref)
        }
        knownRefsCache = refs
        return refs
    }

    private func knownMarkdownFilenames() throws -> Set<String> {
        if let knownFilenamesCache {
            return knownFilenamesCache
        }

        let filenames = Set(try fileIO.enumerateMarkdownFiles(rootURL: rootURL).map(\.lastPathComponent))
        knownFilenamesCache = filenames
        return filenames
    }

    private func loadRecords(at urls: [URL], skipInvalid: Bool = false) throws -> [TaskRecord] {
        if urls.count < 64 {
            return try loadRecordsSerially(at: urls, skipInvalid: skipInvalid)
        }

        let collector = ParallelRecordCollector()

        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let url = urls[index]
            do {
                let record = try loadRecord(at: url)
                collector.append(index: index, record: record)
            } catch {
                if !skipInvalid {
                    collector.capture(error: error)
                }
            }
        }

        if let firstError = collector.firstError {
            throw firstError
        }

        return collector.indexedRecords
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    private func loadRecordsSerially(at urls: [URL], skipInvalid: Bool) throws -> [TaskRecord] {
        var records: [TaskRecord] = []
        records.reserveCapacity(urls.count)

        for url in urls {
            do {
                records.append(try loadRecord(at: url))
            } catch {
                if skipInvalid {
                    continue
                }
                throw error
            }
        }

        return records
    }

    private func loadRecord(at url: URL) throws -> TaskRecord {
        let raw = try fileIO.read(path: url.path)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let document = try codec.parse(markdown: raw, fallbackTitle: fallbackTitle)
        return TaskRecord(identity: TaskFileIdentity(path: url.path), document: document)
    }
}

private final class ParallelRecordCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var indexedRecords: [(Int, TaskRecord)] = []
    private(set) var firstError: Error?

    func append(index: Int, record: TaskRecord) {
        lock.lock()
        indexedRecords.append((index, record))
        lock.unlock()
    }

    func capture(error: Error) {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        lock.unlock()
    }
}
