import ArgumentParser
import Foundation

public struct ListCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tasks from a built-in view"
    )

    @Argument(help: "View to list: today, inbox, upcoming, or all")
    public var view: String?

    @Option(help: "Override the task folder path")
    public var folder: String?

    public init() {}

    public mutating func run() throws {
        let result = try TaskCLIService().list(.init(view: view, folder: folder))
        for line in TaskListOutputFormatter.makeLines(for: result) {
            print(line)
        }
    }
}
