import ArgumentParser
import Foundation

public struct AddCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a task in the selected todo.md folder"
    )

    @Argument(help: "Task title")
    public var title: String

    @Option(help: "Due date as YYYY-MM-DD or a natural-language phrase")
    public var due: String?

    @Option(help: "Project name")
    public var project: String?

    @Option(help: "Priority: none, low, medium, or high")
    public var priority: String?

    @Option(help: "Source tag to write into the task")
    public var source: String = "cli"

    @Option(help: "Override the task folder path")
    public var folder: String?

    public init() {}

    public mutating func run() throws {
        let result = try TaskCLIService().add(
            .init(
                title: title,
                due: due,
                project: project,
                priority: priority,
                source: source,
                folder: folder
            )
        )
        print(AddOutputFormatter.makeLine(for: result))
    }
}
