import ArgumentParser
import Foundation
import TodoMDCore

public enum ValidationOutcome: Sendable {
    case valid
    case invalid
}

public struct ValidationResult: Sendable {
    public let path: String
    public let outcome: ValidationOutcome
    public let message: String?

    public init(path: String, outcome: ValidationOutcome, message: String?) {
        self.path = path
        self.outcome = outcome
        self.message = message
    }
}

public struct ValidationSummary: Sendable {
    public let results: [ValidationResult]

    public init(results: [ValidationResult]) {
        self.results = results
    }

    public var checkedCount: Int { results.count }
    public var validCount: Int { results.filter { $0.outcome == .valid }.count }
    public var invalidCount: Int { results.filter { $0.outcome == .invalid }.count }
}

public struct ValidationOutputFormatter {
    public static func makeLines(for summary: ValidationSummary, verbose: Bool) -> [String] {
        var lines: [String] = []

        for result in summary.results {
            switch result.outcome {
            case .valid:
                if verbose {
                    lines.append("  OK  \(result.path)")
                }
            case .invalid:
                lines.append("FAIL  \(result.path)")
                if let message = result.message, verbose {
                    lines.append("      \(message)")
                }
            }
        }

        lines.append("")
        lines.append("\(summary.checkedCount) files checked: \(summary.validCount) valid, \(summary.invalidCount) invalid")
        return lines
    }
}

public struct ValidationService {
    private let fileManager: FileManager
    private let fileIO: TaskFileIO
    private let readFile: (String) throws -> String
    private let parseDocument: (String, String) throws -> TaskDocument

    public init(
        fileManager: FileManager = .default,
        fileIO: TaskFileIO = TaskFileIO(),
        codec: TaskMarkdownCodec = TaskMarkdownCodec(),
        readFile: ((String) throws -> String)? = nil,
        parseDocument: ((String, String) throws -> TaskDocument)? = nil
    ) {
        self.fileManager = fileManager
        self.fileIO = fileIO
        self.readFile = readFile ?? { path in
            try fileIO.read(path: path)
        }
        self.parseDocument = parseDocument ?? { markdown, fallbackTitle in
            try codec.parse(markdown: markdown, fallbackTitle: fallbackTitle)
        }
    }

    public func validate(inputs: [String]) -> ValidationSummary {
        var results: [ValidationResult] = []

        for input in inputs {
            results.append(contentsOf: validate(input: input))
        }

        return ValidationSummary(results: results)
    }

    private func validate(input: String) -> [ValidationResult] {
        let url = URL(fileURLWithPath: input)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return [
                ValidationResult(
                    path: url.path,
                    outcome: .invalid,
                    message: "Path does not exist"
                )
            ]
        }

        if isDirectory.boolValue {
            do {
                return try fileIO.enumerateMarkdownFiles(rootURL: url)
                    .sorted { $0.path < $1.path }
                    .map(validateFile(at:))
            } catch {
                return [
                    ValidationResult(
                        path: url.path,
                        outcome: .invalid,
                        message: error.localizedDescription
                    )
                ]
            }
        }

        guard fileIO.shouldTrackMarkdownFile(url) else {
            return []
        }

        return [validateFile(at: url)]
    }

    private func validateFile(at url: URL) -> ValidationResult {
        do {
            let content = try readFile(url.path)
            let document = try parseDocument(
                content,
                url.deletingPathExtension().lastPathComponent
            )
            try TaskValidation.validate(document: document)
            return ValidationResult(path: url.path, outcome: .valid, message: nil)
        } catch {
            return ValidationResult(
                path: url.path,
                outcome: .invalid,
                message: error.localizedDescription
            )
        }
    }
}

public struct ValidateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate todo.md task files"
    )

    @Argument(help: "Paths to files or directories to validate")
    public var paths: [String]

    @Flag(help: "Show detailed validation output")
    public var verbose = false

    public init() {}

    public func validate() throws {
        try Self.validateInputPaths(paths)
    }

    public mutating func run() throws {
        let summary = ValidationService().validate(inputs: paths)
        for line in ValidationOutputFormatter.makeLines(for: summary, verbose: verbose) {
            print(line)
        }

        if summary.invalidCount > 0 {
            throw ExitCode.failure
        }
    }

    public static func validateInputPaths(_ paths: [String]) throws {
        guard !paths.isEmpty else {
            throw ValidationError("Missing required argument: provide at least one file or directory path.")
        }
    }
}

public struct TodoMDCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "todomd",
        abstract: "Command-line tools for todo.md task files",
        subcommands: [
            AddCommand.self,
            ListCommand.self,
            DoneCommand.self,
            InboxCommand.self,
            ValidateCommand.self
        ]
    )

    public init() {}
}
