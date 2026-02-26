import Foundation

public enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(any: Any) {
        switch any {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            // NSNumber bridges Bool and numeric values.
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case _ as NSNull:
            self = .null
        case let values as [Any]:
            self = .array(values.map(JSONValue.init(any:)))
        case let dict as [String: Any]:
            self = .object(dict.mapValues(JSONValue.init(any:)))
        default:
            self = .string(String(describing: any))
        }
    }

    public var anyValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .array(let values):
            return values.map(\.anyValue)
        case .object(let dict):
            return dict.mapValues(\.anyValue)
        }
    }
}
