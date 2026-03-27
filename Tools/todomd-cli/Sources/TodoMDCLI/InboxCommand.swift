import ArgumentParser
import Foundation

public struct InboxCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Process dropped markdown files from .inbox"
    )

    @Option(help: "Override the task folder path")
    public var folder: String?

    public init() {}

    public mutating func run() throws {
        let result = try TaskCLIService().inbox(.init(folder: folder))
        print(InboxOutputFormatter.makeLine(for: result))
    }
}
