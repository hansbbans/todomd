import Foundation

public struct TaskRecord: Equatable, Sendable {
    public var identity: TaskFileIdentity
    public var document: TaskDocument

    public init(identity: TaskFileIdentity, document: TaskDocument) {
        self.identity = identity
        self.document = document
    }
}

extension TaskRecord: Identifiable {
    public var id: String { identity.path }
}

public struct TaskRefGenerator: Sendable {
    public init() {}

    public func generate(existingRefs: Set<String>) -> String {
        let length = existingRefs.count > 10_000 ? 6 : 4
        return generate(existingRefs: existingRefs, length: length)
    }

    public static func isValid(ref: String) -> Bool {
        let pattern = #"^t-[0-9a-f]{4,6}$"#
        return ref.range(of: pattern, options: .regularExpression) != nil
    }

    private func generate(existingRefs: Set<String>, length: Int) -> String {
        for _ in 0..<256 {
            let candidate = "t-\(randomHex(length: length))"
            if !existingRefs.contains(candidate) {
                return candidate
            }
        }

        let upperBound = Int(pow(16.0, Double(length)))
        for value in 0..<upperBound {
            let hex = String(value, radix: 16, uppercase: false)
            let padded = String(repeating: "0", count: max(0, length - hex.count)) + hex
            let candidate = "t-\(padded)"
            if !existingRefs.contains(candidate) {
                return candidate
            }
        }

        return "t-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length))"
    }

    private func randomHex(length: Int) -> String {
        var output = ""
        output.reserveCapacity(length)
        for _ in 0..<length {
            output.append("0123456789abcdef".randomElement() ?? "0")
        }
        return output
    }
}

public struct TaskRefResolver: Sendable {
    private let recordsByRef: [String: TaskRecord]

    public init(records: [TaskRecord]) {
        var index: [String: TaskRecord] = [:]
        index.reserveCapacity(records.count)
        for record in records {
            guard let ref = record.document.frontmatter.ref?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ref.isEmpty else { continue }
            index[ref] = record
        }
        self.recordsByRef = index
    }

    public func resolve(ref: String) -> TaskRecord? {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return recordsByRef[normalized]
    }
}
