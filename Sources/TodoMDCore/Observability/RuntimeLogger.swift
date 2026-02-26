import Foundation

public protocol RuntimeLogging {
    func info(_ message: String, metadata: [String: String])
    func error(_ message: String, metadata: [String: String])
}

public struct ConsoleRuntimeLogger: RuntimeLogging {
    public init() {}

    public func info(_ message: String, metadata: [String: String] = [:]) {
        print("[todo.md][INFO] \(message) \(metadata)")
    }

    public func error(_ message: String, metadata: [String: String] = [:]) {
        print("[todo.md][ERROR] \(message) \(metadata)")
    }
}
