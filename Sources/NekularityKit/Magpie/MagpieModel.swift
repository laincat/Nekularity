import Foundation

/// A model a provider serves, as the vendor listed it.
public struct MagpieModel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Token limits, 0 when the vendor did not say.
    public var context: Int64
    public var output: Int64
    public var modalities: [String]
    /// The vendor's owner field, for diagnostics.
    public var vendor: String

    public init(id: String, name: String = "", context: Int64 = 0, output: Int64 = 0,
                modalities: [String] = [], vendor: String = "") {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.context = context
        self.output = output
        self.modalities = modalities
        self.vendor = vendor
    }

    /// What to show beside the id: context size when the vendor gave one.
    public var detail: String {
        guard context > 0 else { return "" }
        if context >= 1000 {
            return "\(Int((Double(context) / 1000).rounded()))K 上下文"
        }
        return "\(context) 上下文"
    }
}
