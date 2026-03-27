import Foundation

public final class InboxFolderService: @unchecked Sendable {
    private enum InvalidInboxContentError: Error {
        case emptyFile
        case invalidUTF8
        case invalidTask(TaskError)
    }

    private let inboxURL: URL
    private let repository: TaskRepository
    private let fileIO: TaskFileIO
    private let codec: TaskMarkdownCodec
    private let minimumFileAge: TimeInterval
    private let deleteInboxFile: ((String) throws -> Void)?
    private let quarantineInvalidInboxFile: ((URL) throws -> Void)?

    public init(
        inboxURL: URL,
        repository: TaskRepository,
        fileIO: TaskFileIO = TaskFileIO(),
        codec: TaskMarkdownCodec = TaskMarkdownCodec(),
        minimumFileAge: TimeInterval = 2
    ) {
        self.inboxURL = inboxURL.standardizedFileURL.resolvingSymlinksInPath()
        self.repository = repository
        self.fileIO = fileIO
        self.codec = codec
        self.minimumFileAge = minimumFileAge
        self.deleteInboxFile = nil
        self.quarantineInvalidInboxFile = nil
    }

    init(
        inboxURL: URL,
        repository: TaskRepository,
        fileIO: TaskFileIO = TaskFileIO(),
        codec: TaskMarkdownCodec = TaskMarkdownCodec(),
        minimumFileAge: TimeInterval = 2,
        deleteInboxFile: ((String) throws -> Void)?,
        quarantineInvalidInboxFile: ((URL) throws -> Void)? = nil
    ) {
        self.inboxURL = inboxURL.standardizedFileURL.resolvingSymlinksInPath()
        self.repository = repository
        self.fileIO = fileIO
        self.codec = codec
        self.minimumFileAge = minimumFileAge
        self.deleteInboxFile = deleteInboxFile
        self.quarantineInvalidInboxFile = quarantineInvalidInboxFile
    }

    public func processInbox(now: Date = Date()) throws -> [InboxIngestResult] {
        guard fileIO.directoryExists(path: inboxURL.path) else { return [] }

        let droppedFiles = try inboxMarkdownFiles()
        var results: [InboxIngestResult] = []
        results.reserveCapacity(droppedFiles.count)

        for fileURL in droppedFiles {
            if try shouldSkip(fileURL: fileURL, now: now) {
                continue
            }

            do {
                let document = try makeDocument(from: fileURL, now: now)
                let stagedURL = try stageInboxFile(fileURL)
                do {
                    results.append(try ingestStagedDocument(document, stagedURL: stagedURL, originalFilename: fileURL.lastPathComponent))
                } catch {
                    try restoreStagedInboxFile(stagedURL, originalFilename: fileURL.lastPathComponent)
                    throw error
                }
            } catch is InvalidInboxContentError {
                do {
                    try quarantineInboxFile(fileURL)
                } catch {
                    continue
                }
            } catch {
                throw error
            }
        }

        return results
    }

    private func inboxMarkdownFiles() throws -> [URL] {
        let fileURLs = try fileIO.fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        )

        return try fileURLs
            .filter { fileIO.shouldTrackMarkdownFile($0) }
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true
            }
            .sorted { $0.path < $1.path }
    }

    private func shouldSkip(fileURL: URL, now: Date) throws -> Bool {
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modificationDate = values.contentModificationDate else { return false }
        return abs(now.timeIntervalSince(modificationDate)) < minimumFileAge
    }

    private func makeDocument(from fileURL: URL, now: Date) throws -> TaskDocument {
        let rawData = try fileIO.readData(path: fileURL.path)
        guard let raw = String(data: rawData, encoding: .utf8) else {
            throw InvalidInboxContentError.invalidUTF8
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvalidInboxContentError.emptyFile
        }

        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        let document: TaskDocument

        if raw.replacingOccurrences(of: "\r\n", with: "\n").hasPrefix("---\n") {
            let parsed: TaskDocument
            do {
                parsed = try codec.parse(markdown: raw, fallbackTitle: fallbackTitle)
            } catch let error as TaskError where isInvalidInboxContent(error) {
                throw InvalidInboxContentError.invalidTask(error)
            }
            document = normalizeParsedDocument(parsed, now: now)
        } else {
            document = TaskDocument(
                frontmatter: TaskFrontmatterV1(
                    title: fallbackTitle,
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    created: now,
                    source: "inbox-drop"
                ),
                body: raw
            )
        }

        return document
    }

    private func stageInboxFile(_ fileURL: URL) throws -> URL {
        let processingURL = inboxURL.appendingPathComponent(".processing", isDirectory: true)
        try fileIO.fileManager.createDirectory(at: processingURL, withIntermediateDirectories: true)

        let stagedURL = uniqueDestination(for: fileURL, in: processingURL)
        try fileIO.fileManager.moveItem(at: fileURL, to: stagedURL)
        return stagedURL
    }

    private func ingestStagedDocument(_ document: TaskDocument, stagedURL: URL, originalFilename: String) throws -> InboxIngestResult {
        let created = try repository.create(document: document, preferredFilename: nil)
        do {
            try deleteSourceInboxFile(path: stagedURL.path)
        } catch {
            // The staged file sits in hidden .processing/, so cleanup failure should not trigger re-imports.
        }

        return InboxIngestResult(
            task: created.document,
            createdPath: created.identity.path,
            originalFilename: originalFilename
        )
    }

    private func normalizeParsedDocument(_ document: TaskDocument, now: Date) -> TaskDocument {
        var copy = document
        if copy.frontmatter.created == .distantPast {
            copy.frontmatter.created = now
        }
        if copy.frontmatter.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || copy.frontmatter.source == "unknown" {
            copy.frontmatter.source = "inbox-drop"
        }
        return copy
    }

    private func isInvalidInboxContent(_ error: TaskError) -> Bool {
        switch error {
        case .parseFailure, .invalidDocument:
            return true
        case .fileNotFound, .ioFailure, .recurrenceFailure, .unsupportedURLAction, .invalidURLParameters:
            return false
        }
    }

    private func deleteSourceInboxFile(path: String) throws {
        if let deleteInboxFile {
            try deleteInboxFile(path)
        } else {
            try fileIO.delete(path: path)
        }
    }

    private func quarantineInboxFile(_ fileURL: URL) throws {
        if let quarantineInvalidInboxFile {
            try quarantineInvalidInboxFile(fileURL)
        } else {
            try moveToErrors(fileURL: fileURL)
        }
    }

    private func restoreStagedInboxFile(_ stagedURL: URL, originalFilename: String) throws {
        let destinationURL = uniqueDestination(for: inboxURL.appendingPathComponent(originalFilename, isDirectory: false), in: inboxURL)
        try fileIO.fileManager.moveItem(at: stagedURL, to: destinationURL)
    }

    private func moveToErrors(fileURL: URL) throws {
        let errorsURL = inboxURL.appendingPathComponent(".errors", isDirectory: true)
        try fileIO.fileManager.createDirectory(at: errorsURL, withIntermediateDirectories: true)

        let destinationURL = uniqueDestination(for: fileURL, in: errorsURL)
        try fileIO.fileManager.moveItem(at: fileURL, to: destinationURL)
    }

    private func uniqueDestination(for fileURL: URL, in directoryURL: URL) -> URL {
        let ext = fileURL.pathExtension
        let stem = fileURL.deletingPathExtension().lastPathComponent
        var candidate = directoryURL.appendingPathComponent(fileURL.lastPathComponent, isDirectory: false)
        var counter = 2

        while fileIO.fileManager.fileExists(atPath: candidate.path) {
            let filename = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = directoryURL.appendingPathComponent(filename, isDirectory: false)
            counter += 1
        }

        return candidate
    }
}
