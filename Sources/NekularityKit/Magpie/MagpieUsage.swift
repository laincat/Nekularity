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

// MARK: - Reading Core's answer

/// Core writes a Go nil slice as `null`, not `[]`.
///
/// A field the vendor did not fill must not turn into a decode failure for the
/// whole report: an unreported list is read as empty, and an unreported figure
/// stays `nil` so the screen does not print a zero nobody measured.
///
/// These live in extensions so the memberwise initialisers stay available for
/// the tests and for a report built in memory.
extension MagpieUsage {
    private enum CodingKeys: String, CodingKey {
        case plan, until, renew, balance, error, user, signIn, resets, windows
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(String.self, forKey: .plan)
        until = try c.decode(String.self, forKey: .until)
        renew = try c.decode(String.self, forKey: .renew)
        balance = try c.decode(String.self, forKey: .balance)
        error = try c.decode(String.self, forKey: .error)
        user = try c.decode(String.self, forKey: .user)
        signIn = try c.decode(String.self, forKey: .signIn)
        resets = try c.decodeIfPresent(Resets.self, forKey: .resets)
        windows = try c.decodeIfPresent([Window].self, forKey: .windows) ?? []
    }
}

extension MagpieUsage.Resets {
    private enum CodingKeys: String, CodingKey {
        case count, until, byWindow, fiveHour, weekly, team, each
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Double.self, forKey: .count)
        until = try c.decode(String.self, forKey: .until)
        byWindow = try c.decode(Bool.self, forKey: .byWindow)
        fiveHour = try c.decode(Double.self, forKey: .fiveHour)
        weekly = try c.decode(Double.self, forKey: .weekly)
        team = try c.decode(Bool.self, forKey: .team)
        each = try c.decodeIfPresent([ResetWindow].self, forKey: .each) ?? []
    }
}

extension MagpieUsage.Window {
    private enum CodingKeys: String, CodingKey {
        case name, used, resetsAt, resetSecs, display, amount, limit, unit, span
        case model, models, notModels, aside, runsOutAt, runsOut, balance
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        used = try c.decodeIfPresent(Double.self, forKey: .used)
        resetsAt = try c.decode(String.self, forKey: .resetsAt)
        resetSecs = try c.decode(Double.self, forKey: .resetSecs)
        display = try c.decode(String.self, forKey: .display)
        amount = try c.decode(Double.self, forKey: .amount)
        limit = try c.decode(Double.self, forKey: .limit)
        unit = try c.decode(String.self, forKey: .unit)
        span = try c.decode(Double.self, forKey: .span)
        model = try c.decode(String.self, forKey: .model)
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
        notModels = try c.decodeIfPresent([String].self, forKey: .notModels) ?? []
        aside = try c.decode(Bool.self, forKey: .aside)
        runsOutAt = try c.decode(String.self, forKey: .runsOutAt)
        runsOut = try c.decode(Double.self, forKey: .runsOut)
        balance = try c.decodeIfPresent(Double.self, forKey: .balance)
    }
}
