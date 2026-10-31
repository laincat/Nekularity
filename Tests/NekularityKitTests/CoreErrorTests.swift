import Foundation
import Testing
@testable import NekularityKit

/// Core speaks English; the interface is Chinese. The mapping is what a
/// reader sees, so its cases are pinned here.
@Suite struct CoreErrorTests {
    @Test func knownFailuresReadAsChinese() {
        #expect(CoreError.readable("context canceled") == "操作已取消")
        #expect(CoreError.readable("rpc error: no such source") == "找不到这个漫画源,可能已被删除")
        #expect(CoreError.readable("source not installed") == "漫画源还未安装")
        #expect(CoreError.readable("request timeout") == "网络超时,请稍后重试")
        #expect(CoreError.readable("cloudflare challenge") == "源要求人机验证或拒绝了请求")
    }

    /// ATS refuses plain http inside the app, before any network call. It reads
    /// like a connection failure, so it gets its own sentence.
    @Test func aBlockedPlainHTTPConnectionSaysWhy() {
        let text = CoreError.readable("Error Domain=NSURLErrorDomain Code=-1022 \"The resource could not be loaded because the App Transport Security policy requires the use of a secure connection.\"")
        // The app allows http, so seeing this means the configuration did not take
        // effect — the message says how to report it instead of telling the user to
        // fix the source.
        #expect(text.contains("ATS"))
        #expect(text.contains("反馈"))
    }

    @Test func anUnknownMessageKeepsCoresWording() {
        // A Chinese prefix, then Core's own words, so a report still carries
        // what happened without showing a bare English sentence.
        let text = CoreError.readable("unexpected status 500")
        #expect(text.hasPrefix("源返回错误:"))
        #expect(text.contains("unexpected status 500"))
        #expect(CoreError.readable("") == "操作失败,源没有给出原因")
    }

    @Test func anErrorReportsTheReadableForm() {
        let error = CoreError("no such source")
        #expect(error.errorDescription == "找不到这个漫画源,可能已被删除")
        #expect(error.isCancelled == false)
        #expect(CoreError("context canceled").isCancelled)
    }
}
