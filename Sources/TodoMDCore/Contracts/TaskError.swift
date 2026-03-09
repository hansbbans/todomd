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

extension TaskError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDocument(let message),
             .parseFailure(let message),
             .fileNotFound(let message),
             .ioFailure(let message),
             .recurrenceFailure(let message),
             .unsupportedURLAction(let message),
             .invalidURLParameters(let message):
            return message
        }
    }
}
