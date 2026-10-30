import Foundation

/// What a package's plugin offers, as Core read it from the package itself.
public struct MagpieAuthSpec: Codable, Sendable, Hashable {
    public struct Method: Codable, Sendable, Hashable {
        /// One field a key-based method asks for: an API token, an account id.
        /// Without these the screen has nowhere to type the key, which is why a
        /// key-based provider looked broken rather than unsigned-in.
        public struct Prompt: Codable, Sendable, Hashable {
            public var key: String
            /// "password" or "text"; anything else is shown as text.
            public var type: String
            public var message: String
            public var placeholder: String

            public init(key: String, type: String = "text", message: String = "", placeholder: String = "") {
                self.key = key
                self.type = type
                self.message = message
                self.placeholder = placeholder
            }

            public var isSecret: Bool { type == "password" }
        }

        public var index: Int
        public var label: String
        public var kind: String
        public var hint: String
        public var prompts: [Prompt]

        public init(index: Int, label: String, kind: String = "", hint: String = "", prompts: [Prompt] = []) {
            self.index = index
            self.label = label
            self.kind = kind
            self.hint = hint
            self.prompts = prompts
        }

        /// A method that collects its fields in the app rather than on a page.
        public var collectsInput: Bool { !prompts.isEmpty }
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
