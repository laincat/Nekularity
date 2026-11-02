import Darwin
import XCTest

/// The three link cases need a local HTTPS fixture on ports 18791/18792 plus a
/// trusted CA in the simulator, which lives outside the repository. Skip rather
/// than fail when that harness is absent, so a clean machine stays green and
/// nobody mistakes an unreachable server for a product defect.
private func fixtureListening(port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if result != 0 {
        guard errno == EINPROGRESS else { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, 500) == 1 else { return false }
        var code: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) == 0 else { return false }
        guard code == 0 else { return false }
    }
    return true
}

final class ZZThemeLinkTests: XCTestCase {
    private func requireFixture() throws {
        let missing = [18791, 18792].filter { !fixtureListening(port: UInt16($0)) }
        if !missing.isEmpty {
            throw XCTSkip("theme fixture is not listening on 127.0.0.1:\(missing); see docs/UNVERIFIED.md")
        }
    }
    private func settings(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["设置"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
    }
    private func openLink(_ app: XCUIApplication) {
        let link = app.buttons.matching(NSPredicate(format: "identifier == 'settings.themeFromLink'")).firstMatch
        for _ in 0..<6 {
            if link.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "no theme link entry")
        link.tap()
    }
    private func install(_ app: XCUIApplication, _ url: String) {
        openLink(app)
        let field = app.textFields.matching(NSPredicate(format: "identifier == 'settings.themeLinkField'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no URL field")
        field.tap()
        field.typeText(url)
        XCTAssertEqual(field.value as? String, url, "URL did not reach field")
        let button = app.buttons.matching(NSPredicate(format: "identifier == 'settings.themeLinkInstall'")).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no install button")
        button.tap()
    }
    /// Installs and selects the good theme. The invalid-JSON case needs a
    /// baseline of its own: relying on the success case to have run first made
    /// the assertion fail on a fresh simulator, which looks like a product bug.
    private func installAndSelectGood(_ app: XCUIApplication) {
        install(app, "https://127.0.0.1:18791/valid.json")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 25), "baseline theme was not installed")
        XCTAssertTrue(alert.label.contains("已安装主题"), "unexpected baseline result: \(alert.label)")
        alert.buttons["好"].tap()
        let theme = app.buttons.matching(NSPredicate(format: "label CONTAINS 'P1 HTTPS Proof'")).firstMatch
        for _ in 0..<6 { if theme.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(theme.waitForExistence(timeout: 10), "baseline theme missing")
        theme.tap()
        XCTAssertTrue(theme.images.matching(NSPredicate(format: "identifier == 'checkmark'")).firstMatch.exists,
                      "baseline theme was not selected")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testHTTPSThemeInstallSelectAndRelaunch() throws {
        try requireFixture()
        let app = XCUIApplication(); app.launch(); settings(app)
        install(app, "https://127.0.0.1:18791/valid.json")
        let alert = app.alerts.firstMatch
        if !alert.waitForExistence(timeout: 25) { capture(app, "https-success-missing") }
        XCTAssertTrue(alert.exists, "HTTPS success alert missing")
        XCTAssertTrue(alert.label.contains("已安装主题"), "unexpected success: \(alert.label)")
        alert.buttons["好"].tap()
        let theme = app.buttons.matching(NSPredicate(format: "label CONTAINS 'P1 HTTPS Proof'")).firstMatch
        for _ in 0..<6 { if theme.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(theme.waitForExistence(timeout: 10), "installed theme missing")
        theme.tap()
        capture(app, "https-selected")
        app.terminate(); app.launch(); settings(app)
        for _ in 0..<6 { if theme.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(theme.waitForExistence(timeout: 10), "theme missing after relaunch")
        capture(app, "https-relaunched")
        XCTAssertTrue(theme.images.matching(NSPredicate(format: "identifier == 'checkmark'")).firstMatch.exists,
                      "theme is not selected after relaunch")
    }
    func testHTTPSInvalidThemeShowsErrorAndPreservesSelection() throws {
        try requireFixture()
        let app = XCUIApplication(); app.launch(); settings(app)
        // Establish the baseline in this test rather than inheriting whatever a
        // previous test left behind.
        installAndSelectGood(app)
        capture(app, "invalid-baseline")
        install(app, "https://127.0.0.1:18791/invalid.json")
        let alert = app.alerts.firstMatch
        if !alert.waitForExistence(timeout: 20) { capture(app, "https-error-missing") }
        XCTAssertTrue(alert.exists, "invalid JSON error alert missing")
        capture(app, "https-error")
        alert.buttons["好"].tap()
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        let theme = app.buttons.matching(NSPredicate(format: "label CONTAINS 'P1 HTTPS Proof'")).firstMatch
        for _ in 0..<6 { if theme.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(theme.waitForExistence(timeout: 10), "good theme disappeared after invalid install")
        XCTAssertTrue(theme.images.matching(NSPredicate(format: "identifier == 'checkmark'")).firstMatch.exists,
                      "good theme no longer selected after invalid install")
    }
    func testHTTPThemeLinkIsRejected() throws {
        try requireFixture()
        let app = XCUIApplication(); app.launch(); settings(app)
        install(app, "http://127.0.0.1:18792/http.json")
        let alert = app.alerts.firstMatch
        if !alert.waitForExistence(timeout: 20) { capture(app, "http-result-missing") }
        XCTAssertTrue(alert.exists, "HTTP rejection alert missing")
        capture(app, "http-result")
        XCTAssertTrue(alert.label.contains("https"), "HTTP rejection did not name HTTPS: \(alert.label)")
        alert.buttons["好"].tap()
        let httpTheme = app.buttons.matching(NSPredicate(format: "label CONTAINS 'P1 HTTP Proof'")).firstMatch
        XCTAssertFalse(httpTheme.exists, "HTTP theme appeared in the list after rejection")
    }
}
