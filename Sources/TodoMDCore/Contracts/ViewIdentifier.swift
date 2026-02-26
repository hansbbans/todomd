import Foundation

public enum BuiltInView: String, CaseIterable, Sendable {
    case inbox
    case today
    case upcoming
    case anytime
    case someday
    case flagged
}

public enum ViewIdentifier: Hashable, Sendable, RawRepresentable {
    case builtIn(BuiltInView)
    case area(String)
    case project(String)
    case tag(String)
    case custom(String)

    public init(rawValue: String) {
        if let builtIn = BuiltInView(rawValue: rawValue) {
            self = .builtIn(builtIn)
            return
        }

        if rawValue.hasPrefix("area:") {
            self = .area(String(rawValue.dropFirst("area:".count)))
            return
        }

        if rawValue.hasPrefix("project:") {
            self = .project(String(rawValue.dropFirst("project:".count)))
            return
        }

        if rawValue.hasPrefix("tag:") {
            self = .tag(String(rawValue.dropFirst("tag:".count)))
            return
        }

        self = .custom(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .builtIn(let view):
            return view.rawValue
        case .area(let name):
            return "area:\(name)"
        case .project(let name):
            return "project:\(name)"
        case .tag(let name):
            return "tag:\(name)"
        case .custom(let value):
            return value
        }
    }
}
