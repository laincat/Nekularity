import XCTest

final class ZZThemeLinkTests: XCTestCase {
    private func settings(_ app: XCUIApplication) {
        let tab = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'tab.settings'")).firstMatch
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
    private func capture(_ app: XCUIApplication, _ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testHTTPSThemeInstallSelectAndRelaunch() throws {
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
        let app = XCUIApplication(); app.launch(); settings(app)
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
