import Foundation

public enum YAMLValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([YAMLValue])
    case object([String: YAMLValue])

    public init(any: Any) {
        switch any {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .int(value)
        case let value as Double:
            self = .double(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case _ as NSNull:
            self = .null
        case let values as [Any]:
            self = .array(values.map(YAMLValue.init(any:)))
        case let dict as [String: Any]:
            self = .object(dict.mapValues(YAMLValue.init(any:)))
        default:
            self = .string(String(describing: any))
        }
    }

    public var anyValue: Any {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
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
