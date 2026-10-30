import Foundation

/// What a package's plugin offers, as Core read it from the package itself.
public struct MagpieAuthSpec: Codable, Sendable, Hashable {
    public struct Method: Codable, Sendable, Hashable {
        public var index: Int
        public var label: String
        public var kind: String
        public var hint: String

        public init(index: Int, label: String, kind: String = "", hint: String = "") {
            self.index = index
            self.label = label
            self.kind = kind
            self.hint = hint
        }
    }

    public struct Option: Codable, Sendable, Hashable {
        public var key: String
        public var label: String
        public var description: String
        public var confirm: String
        public var `default`: Bool

        public init(key: String, label: String, description: String = "", confirm: String = "",
                    default value: Bool = false) {
            self.key = key
            self.label = label
            self.description = description
            self.confirm = confirm
            self.default = value
        }
    }

    public var provider: String
    public var methods: [Method]
    public var options: [Option]
    public var hasUsage: Bool
    public var hasLoader: Bool

    /// The first method, which is what a single-button sign-in uses.
    public var defaultMethod: Method? { methods.first }
}
