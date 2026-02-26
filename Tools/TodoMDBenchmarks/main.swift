import Foundation
import TodoMDCore

private struct BenchmarkResult: Codable {
    let taskCount: Int
    let changedCount: Int
    let coldSyncMilliseconds: Double
    let incrementalSyncMilliseconds: Double
    let queryMilliseconds: Double
}

private struct BenchmarkArguments {
    var counts: [Int] = [500, 1000, 5000]
    var changedCount: Int = 10
    var json: Bool = false

    init(arguments: [String]) {
        var iterator = arguments.makeIterator()
        _ = iterator.next()

        while let argument = iterator.next() {
            switch argument {
            case "--counts":
                if let raw = iterator.next() {
                    let parsed = raw
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .filter { $0 > 0 }
                    if !parsed.isEmpty {
                        counts = parsed
                    }
                }
            case "--changed":
                if let raw = iterator.next(), let value = Int(raw), value > 0 {
                    changedCount = value
                }
            case "--json":
                json = true
            default:
                continue
            }
        }
    }
}

private enum BenchmarkRunner {
    static func run(taskCount: Int, changedCount: Int) throws -> BenchmarkResult {
        let root = try makeTempRoot(taskCount: taskCount)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository, conflictDetectionEnabled: false)
        let queryEngine = TaskQueryEngine()
        let fileIO = TaskFileIO()
        let codec = TaskMarkdownCodec()

        try createTasks(count: taskCount, rootURL: root, fileIO: fileIO, codec: codec)

        var coldRecords: [TaskRecord] = []
        let coldSyncMilliseconds = try measureMilliseconds {
            coldRecords = try watcher.synchronize(now: Date()).records
        }

        let changedPaths = try repository
            .loadAll()
            .map(\.identity.path)
            .sorted()
            .prefix(changedCount)

        for path in changedPaths {
            _ = try repository.update(path: path) { document in
                document.frontmatter.title = "\(document.frontmatter.title) updated"
                document.frontmatter.modified = Date()
            }
        }

        let incrementalSyncMilliseconds = try measureMilliseconds {
            _ = try watcher.synchronize(now: Date())
        }

        let today = LocalDate.today(in: .current)
        let queryMilliseconds = try measureMilliseconds {
            let matches = coldRecords.filter { queryEngine.matches($0, view: .builtIn(.today), today: today) }
            _ = matches.count
        }

        return BenchmarkResult(
            taskCount: taskCount,
            changedCount: min(changedCount, taskCount),
            coldSyncMilliseconds: coldSyncMilliseconds,
            incrementalSyncMilliseconds: incrementalSyncMilliseconds,
            queryMilliseconds: queryMilliseconds
        )
    }

    private static func createTasks(count: Int, rootURL: URL, fileIO: TaskFileIO, codec: TaskMarkdownCodec) throws {
        for index in 0..<count {
            let created = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            let frontmatter = TaskFrontmatterV1(
                title: "Benchmark Task \(index)",
                status: .todo,
                due: nil,
                defer: nil,
                scheduled: nil,
                priority: .none,
                flagged: index % 17 == 0,
                area: index % 5 == 0 ? "Work" : nil,
                project: index % 7 == 0 ? "Bench" : nil,
                tags: index % 11 == 0 ? ["benchmark"] : [],
                recurrence: nil,
                estimatedMinutes: nil,
                description: nil,
                created: created,
                modified: created,
                completed: nil,
                source: "benchmark"
            )

            let document = TaskDocument(frontmatter: frontmatter, body: "body \(index)")
            let content = try codec.serialize(document: document)
            let path = rootURL.appendingPathComponent(String(format: "task-%05d.md", index)).path
            try fileIO.write(path: path, content: content)
        }
    }

    private static func makeTempRoot(taskCount: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todomd-benchmark-\(taskCount)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func measureMilliseconds(_ block: () throws -> Void) throws -> Double {
        let start = ContinuousClock.now
        try block()
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds)
        let attoseconds = Double(duration.components.attoseconds)
        return (seconds * 1_000) + (attoseconds / 1_000_000_000_000_000)
    }
}

@main
private struct TodoMDBenchmarksMain {
    static func main() throws {
        let arguments = BenchmarkArguments(arguments: CommandLine.arguments)
        var results: [BenchmarkResult] = []

        for taskCount in arguments.counts {
            let result = try BenchmarkRunner.run(taskCount: taskCount, changedCount: arguments.changedCount)
            results.append(result)
        }

        if arguments.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
            return
        }

        print("todo.md benchmark")
        for result in results {
            print(
                "tasks=\(result.taskCount) " +
                "changed=\(result.changedCount) " +
                "cold_sync_ms=\(String(format: "%.2f", result.coldSyncMilliseconds)) " +
                "incremental_sync_ms=\(String(format: "%.2f", result.incrementalSyncMilliseconds)) " +
                "query_ms=\(String(format: "%.2f", result.queryMilliseconds))"
            )
        }
    }
}
