import Foundation
import Testing
@testable import NekularityKit

/// What the island says has to be readable at a glance, which means the arithmetic and
/// the wording are worth testing even though the drawing cannot be.
@Suite("Download progress text")
struct DownloadActivityTextTests {
    @Test("progress is a fraction that does not divide by zero")
    func fraction() {
        #expect(DownloadProgressText.fraction(done: 0, total: 10) == 0)
        #expect(DownloadProgressText.fraction(done: 5, total: 10) == 0.5)
        #expect(DownloadProgressText.fraction(done: 10, total: 10) == 1)
        // A chapter whose page list never arrived is not "0% of nothing".
        #expect(DownloadProgressText.fraction(done: 0, total: 0) == 1)
    }

    @Test("the percentage rounds down, so 99.6% is not shown as done")
    func percent() {
        #expect(DownloadProgressText.percent(done: 0, total: 20) == 0)
        #expect(DownloadProgressText.percent(done: 19, total: 20) == 95)
        #expect(DownloadProgressText.percent(done: 20, total: 20) == 100)
    }

    @Test("a failure wins over a number, and finishing says so")
    func wording() {
        #expect(DownloadProgressText.compact(done: 3, total: 10, failure: nil) == "30%")
        #expect(DownloadProgressText.compact(done: 3, total: 10, failure: "网络不通") == "失败")
        #expect(DownloadProgressText.compact(done: 10, total: 10, failure: nil) == "已保存")
        #expect(DownloadProgressText.detail(done: 3, total: 10, failure: nil) == "第 3/10 页")
        #expect(DownloadProgressText.detail(done: 10, total: 10, failure: nil) == "10 页已保存")
        #expect(DownloadProgressText.detail(done: 0, total: 0, failure: nil) == "正在准备")
    }
}
