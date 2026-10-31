import Foundation

/// Turns Core's English refusals into a sentence a user can act on, while keeping
/// Core's own words for diagnosis.
///
/// Core reports a package it will not run with a stable sentence: TypeScript is
/// refused as TypeScript, a Node dependency is refused as a dependency. A user
/// installing a downloaded package should not have to read Go error text to learn
/// that the package needs Node, so the two common refusals get a Chinese sentence
/// and the original detail is appended.
public enum MagpieErrorText {
    /// A Chinese explanation of `detail`, or `nil` when nothing better can be said
    /// than what Core said — inventing a vague message would hide the real cause.
    public static func explain(_ detail: String) -> String? {
        let lower = detail.lowercased()
        if lower.contains("is typescript") || lower.contains("unsupported source language") {
            return "这个插件包是 TypeScript 源码。当前运行时只执行 JavaScript,请改用编译后的包。"
        }
        if lower.contains("host adapter or bundled dependency") || lower.contains("node:") {
            return "这个插件包依赖 Node 内置模块或没有随包附带的 npm 依赖,当前运行时没有 Node。"
        }
        return nil
    }

    /// What the screens show: the explanation plus Core's detail, or Core's detail
    /// alone when there is no explanation.
    public static func message(for detail: String) -> String {
        guard let explanation = explain(detail) else { return detail }
        return "\(explanation)\n(Core: \(detail))"
    }
}
