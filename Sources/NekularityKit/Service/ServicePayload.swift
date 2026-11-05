import Foundation

/// The payload a service call carries.
///
/// Core accepts JSON text and refuses anything else, so the client checks it
/// first: a person who typed a stray brace should be told where they are, not
/// have a call rejected by an engine message. Empty means `null`, which is what
/// a method that takes nothing expects.
public enum ServicePayload {
    /// The text to send for what a person typed: empty becomes `null`.
    public static func normalized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "null" : trimmed
    }

    /// Whether the text parses as JSON. `normalized` first, so empty passes.
    public static func isValid(_ text: String) -> Bool {
        let body = normalized(text)
        guard let data = body.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
