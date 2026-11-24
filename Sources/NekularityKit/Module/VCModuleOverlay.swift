/// The caller's current reading preferences and the effective values after applying modules.
public struct VCModuleBaseSettings: Equatable, Sendable {
    public var readerPageGap: Int
    public var readerKeepScreenOn: Bool
    public var readerLayout: String
    public var readerRightToLeft: Bool
    public var readerAutoNext: Bool

    public init(readerPageGap: Int = 0, readerKeepScreenOn: Bool = false, readerLayout: String = "vertical",
                readerRightToLeft: Bool = false, readerAutoNext: Bool = false) {
        self.readerPageGap = readerPageGap
        self.readerKeepScreenOn = readerKeepScreenOn
        self.readerLayout = readerLayout
        self.readerRightToLeft = readerRightToLeft
        self.readerAutoNext = readerAutoNext
    }
}

public enum VCModuleOverlay {
    /// Later enabled modules win each key. Recompute with the current base on every read.
    public static func resolve(base: VCModuleBaseSettings, modules: [InstalledVCModule]) -> VCModuleBaseSettings {
        var effective = base
        for module in modules where module.enabled {
            for (key, value) in module.document.settings {
                switch (key, value) {
                case (.readerPageGap, .int(let gap)): effective.readerPageGap = gap
                case (.readerKeepScreenOn, .bool(let keep)): effective.readerKeepScreenOn = keep
                case (.readerLayout, .string(let layout)): effective.readerLayout = layout
                case (.readerRightToLeft, .bool(let rtl)): effective.readerRightToLeft = rtl
                case (.readerAutoNext, .bool(let auto)): effective.readerAutoNext = auto
                default: break
                }
            }
        }
        return effective
    }
}
