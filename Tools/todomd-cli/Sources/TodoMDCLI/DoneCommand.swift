import ArgumentParser
import Foundation

public struct DoneCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Complete a task by ref"
    )

    @Argument(help: "Task ref, for example t-1a2b")
    public var ref: String

    @Option(help: "Override the task folder path")
    public var folder: String?

    public init() {}

    public mutating func run() throws {
        let result = try TaskCLIService().done(.init(ref: ref, folder: folder))
        print(DoneOutputFormatter.makeLine(for: result))
    }
}
