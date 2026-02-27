import Foundation

public struct TaskFileIO {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func enumerateMarkdownFiles(rootURL: URL) throws -> [URL] {
        let normalizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory {
                urls.append(url.standardizedFileURL.resolvingSymlinksInPath())
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    public func enumerateMarkdownFingerprints(rootURL: URL) throws -> [TaskFileFingerprint] {
        let normalizedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var fingerprints: [TaskFileFingerprint] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if values.isDirectory == true {
                continue
            }
            fingerprints.append(
                TaskFileFingerprint(
                    path: resolved.path,
                    fileSize: UInt64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? Date.distantPast
                )
            )
        }

        return fingerprints.sorted { $0.path < $1.path }
    }

    public func read(path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: url.path) else {
            throw TaskError.fileNotFound(path)
        }

        try ensureLocalAvailability(for: url)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readError: Error?
        var content = ""
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                content = try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw TaskError.ioFailure("Failed to read file at \(path): \(coordinationError.localizedDescription)")
        }

        if let readError {
            throw TaskError.ioFailure("Failed to read file at \(path): \(readError.localizedDescription)")
        }

        return content
    }

    private func ensureLocalAvailability(for url: URL) throws {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isUbiquitousItem == true else { return }

        if values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
            return
        }

        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }

        throw TaskError.ioFailure("iCloud file is not downloaded yet: \(url.path)")
    }

    public func write(path: String, content: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw TaskError.ioFailure("Failed to write file at \(path): \(coordinationError.localizedDescription)")
        }

        if let writeError {
            throw TaskError.ioFailure("Failed to write file at \(path): \(writeError.localizedDescription)")
        }
    }

    public func delete(path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw TaskError.ioFailure("Failed to delete file at \(path): \(error.localizedDescription)")
        }
    }

    public func fingerprint(for path: String) throws -> TaskFileFingerprint {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return TaskFileFingerprint(
            path: url.path,
            fileSize: UInt64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? Date.distantPast
        )
    }
}
