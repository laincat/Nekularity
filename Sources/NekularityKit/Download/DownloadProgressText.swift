import Foundation

/// What a download's progress looks like as text and as a fraction.
///
/// Kept away from ActivityKit on purpose: the kit's tests run on macOS, where
/// ActivityKit does not exist, and the part worth testing is the arithmetic and the
/// wording, not the framework.
public enum DownloadProgressText {
    /// Progress in 0...1. A total of zero is finished rather than a division by zero.
    public static func fraction(done: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// The percentage, rounded the way a person reads it: 99.6% is still not done.
    public static func percent(done: Int, total: Int) -> Int {
        guard total > 0 else { return 100 }
        let raw = Double(done) / Double(total) * 100
        return min(100, max(0, Int(raw)))
    }

    /// The one line the compact presentation has room for.
    public static func compact(done: Int, total: Int, failure: String?) -> String {
        if let failure, !failure.isEmpty { return "失败" }
        if total > 0 && done >= total { return "已保存" }
        return "\(percent(done: done, total: total))%"
    }

    /// The line under the title in the expanded presentation.
    public static func detail(done: Int, total: Int, failure: String?) -> String {
        if let failure, !failure.isEmpty { return failure }
        if total <= 0 { return "正在准备" }
        if done >= total { return "\(total) 页已保存" }
        return "第 \(done)/\(total) 页"
    }
}

/// Which chapter a single Live Activity should be telling about.
///
/// The island has room for one story. Starting a new one every time a second chapter
/// begins would flip the text under the user's eyes, so a chapter that is already
/// shown keeps the island until it finishes.
public enum DownloadActivityChoice {
    public static func chapter(active: [String], shown: String?) -> String? {
        if let shown, active.contains(shown) { return shown }
        return active.sorted().first
    }
}
