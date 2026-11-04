import XCTest
@testable import NekularityKit

/// Core answers a login handle it never issued — the source was updated or
/// removed while the login page was open. The login has to stop for that, and
/// must keep waiting for the ordinary errors a source throws on a page it does
/// not recognise.
final class WebviewLoginHandleTests: XCTestCase {
    func testTheExpiredHandleIsRecognised() {
        let error = CoreError("js: webview login handle is no longer valid")
        XCTAssertTrue(error.isWebviewHandleGone)
    }

    func testOrdinarySourceErrorsKeepWaiting() {
        for message in [
            "js: checkStatus: Error: this page is not the login page",
            "js: no such callback",
            "context canceled",
        ] {
            XCTAssertFalse(CoreError(message).isWebviewHandleGone, message)
        }
    }

    func testTheSentenceNamesTheChangedSource() {
        let text = CoreError.readable("js: webview login handle is no longer valid")
        XCTAssertTrue(text.contains("登录"), text)
        XCTAssertTrue(text.contains("失效") || text.contains("删除"), text)
        XCTAssertFalse(text.contains("no longer valid"), "Core's English should not reach the interface")
    }
}
