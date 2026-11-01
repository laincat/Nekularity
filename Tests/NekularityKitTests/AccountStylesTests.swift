import XCTest
@testable import NekularityKit

/// Which login styles a source declares decides what the interface draws, and
/// the three styles do not overlap: ehentai has no password login at all, while
/// nhentai offers nothing but the in-page one.
final class AccountStylesTests: XCTestCase {
    func testAPasswordSourceNeedsAnAccount() {
        let styles = AccountStyles(password: true, webview: false, cookies: false, logout: true)
        XCTAssertTrue(styles.needsAccount)
        XCTAssertFalse(styles.onlyInPage)
    }

    /// An in-page login needs a browser the client does not host, so it is the
    /// one case the interface must state rather than draw.
    func testOnlyInPageIsRecognised() {
        let styles = AccountStyles(password: false, webview: true, cookies: false, logout: true)
        XCTAssertTrue(styles.onlyInPage)
        XCTAssertTrue(styles.needsAccount)
    }

    /// ehentai offers both an in-page login and a cookie form, so the cookie
    /// form is drawn: something can be done.
    func testCookieStyleBeatsInPage() {
        let styles = AccountStyles(password: false, webview: true, cookies: true, logout: true)
        XCTAssertFalse(styles.onlyInPage)
        XCTAssertTrue(styles.needsAccount)
    }

    /// A source that needs no account gets no form at all.
    func testNoAccountDrawsNothing() {
        let styles = AccountStyles(password: false, webview: false, cookies: false, logout: false)
        XCTAssertFalse(styles.needsAccount)
        XCTAssertFalse(styles.onlyInPage)
    }
}
