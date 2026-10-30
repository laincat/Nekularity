import Foundation

/// What a press of the check-in came to.
///
/// The vocabulary is fixed so this screen does not have to read a vendor's
/// sentence — and so a captcha is never mistaken for a success.
public struct MagpieCheckin: Codable, Sendable, Hashable {
    public enum Outcome: String, Codable, Sendable {
        case claimed, done, ineligible, inactive, captcha, failed
    }

    public var outcome: Outcome
    public var credit: String
    public var streak: Double
    /// The vendor's own words, or — when it answered something outside the set —
    /// the host naming that answer.
    public var message: String
    /// When the vendor's own day turns, when it said.
    public var until: String

    /// One sentence for the user, in the app's language.
    public var summary: String {
        switch outcome {
        case .claimed:
            return credit.isEmpty ? "已签到" : "已签到,获得 \(credit)"
        case .done:
            return "今天已经签过了"
        case .ineligible:
            return message.isEmpty ? "这个账号不能参加" : message
        case .inactive:
            return message.isEmpty ? "现在没有可签到的活动" : message
        case .captcha:
            return "供应商要求人机验证,请到它自己的 App 里签到"
        case .failed:
            return message.isEmpty ? "签到失败" : message
        }
    }

    public var succeeded: Bool { outcome == .claimed || outcome == .done }
}
