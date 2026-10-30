import Foundation

/// An account's usage in the shape every provider shares.
///
/// Core normalises whatever the vendor answered, so this mirrors one shape and
/// keeps the difference that matters: a share the vendor did not give is `nil`,
/// not zero.
public struct MagpieUsage: Codable, Sendable, Hashable {
    public struct Resets: Codable, Sendable, Hashable {
        public var count: Double
        public var until: String
        public var byWindow: Bool
        public var fiveHour: Double
        public var weekly: Double
        public var team: Bool
        public var each: [ResetWindow]

        public struct ResetWindow: Codable, Sendable, Hashable {
            public var until: String
            public var window: String
        }
    }

    public struct Window: Codable, Sendable, Hashable, Identifiable {
        public var name: String
        /// Percent used; past 100 when overspent, `nil` when the vendor did not
        /// say. Never invented as zero.
        public var used: Double?
        public var resetsAt: String
        public var resetSecs: Double
        public var display: String
        public var amount: Double
        public var limit: Double
        public var unit: String
        public var span: Double
        public var model: String
        public var models: [String]
        public var notModels: [String]
        /// Display only: kept out of routing.
        public var aside: Bool
        public var runsOutAt: String
        public var runsOut: Double
        /// A prepaid wallet's figure, `nil` when unsaid.
        public var balance: Double?

        public var id: String { name + "|" + model + "|" + unit }

        /// What to show as the amount: a count when the vendor gave one, a
        /// percentage when it gave a share, and the vendor's own words when it
        /// gave neither.
        public var summary: String {
            if let balance, balance > 0 || amount == 0 {
                return "\(MagpieUsage.number(balance)) \(unit.isEmpty ? "" : unit)".trimmingCharacters(in: .whitespaces)
            }
            if amount > 0 && limit > 0 {
                return "\(MagpieUsage.number(amount)) / \(MagpieUsage.number(limit)) \(unit)".trimmingCharacters(in: .whitespaces)
            }
            if let used {
                return "\(MagpieUsage.number(used))%"
            }
            return display.isEmpty ? "没有报告用量" : display
        }
    }

    public var plan: String
    public var until: String
    public var renew: String
    public var balance: String
    public var error: String
    public var user: String
    public var signIn: String
    public var resets: Resets?
    public var windows: [Window]

    /// A whole number without a trailing ".0", since quotas are counts.
    static func number(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
