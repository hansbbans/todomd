import Foundation

public enum TaskError: Error, Equatable, Sendable {
    case invalidDocument(String)
    case parseFailure(String)
    case fileNotFound(String)
    case ioFailure(String)
    case recurrenceFailure(String)
    case unsupportedURLAction(String)
    case invalidURLParameters(String)
}
