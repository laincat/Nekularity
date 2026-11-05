import XCTest
import UIKit

/// P1 evidence: the board at a real 3-column width.
final class ZZThreeColumnTests: XCTestCase {
    func testLandscapeBoardHasThreeColumns() throws {
        // The board drops to one column at accessibility text sizes on purpose —
        // a three-column board at that size would be unreadable. This case is about
        // the width bands, so it says so instead of failing. The runner is an app on
        // the same simulator, so it reads the same system text-size setting.
        if UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory {
            throw XCTSkip("three-column geometry is not what the board does at accessibility sizes")
        }
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        // iPhone draws the sections in a bottom tab bar, iPad in a compact top bar
        // of plain buttons outside any `TabBar` element.
        let inBar = app.tabBars.buttons["发现"].firstMatch
        let discover = inBar.exists ? inBar
            : app.buttons.matching(NSPredicate(format: "label == %@", "发现")).firstMatch
        XCTAssertTrue(discover.waitForExistence(timeout: 30), "no discover tab")
        discover.tap()
        let edit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'discover.edit'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "discovery did not draw")
        sleep(1)

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "no board scroll view")
        let width = scroll.frame.width
        // This case is the phone's 3-column band. On an iPad the same board is four
        // columns by design, so the band does not exist there and asserting it would
        // report a correct screen as a failure.
        if width >= 900 {
            throw XCTSkip("content width is \(width): the 4-column band, not this case's 3-column band")
        }
        XCTAssertGreaterThanOrEqual(width, 560, "content width is \(width), below the 3-column band")

        edit.tap()
        let ids = ["history", "favorites", "continueWatching"]
        var originals: [String: String] = [:]
        func choose(_ id: String, _ choice: String) {
            let control = app.buttons.matching(NSPredicate(format: "identifier == %@", "home.size.template:\(id)")).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10), "size control missing: \(id)")
            // A control can be laid out and still sit outside the viewport, where
            // tapping it fails with an invalid activation point.
            if !control.frame.intersects(app.windows.firstMatch.frame) { app.swipeUp() }
            control.tap()
            let option = app.sheets.firstMatch.exists ? app.sheets.firstMatch.buttons[choice] : app.alerts.firstMatch.buttons[choice]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "size option missing: \(choice)")
            option.tap()
        }
        for id in ids {
            let control = app.buttons.matching(NSPredicate(format: "identifier == %@", "home.size.template:\(id)")).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10), "size missing \(id)")
            originals[id] = control.label
            if control.label != "小" { choose(id, "小") }
        }
        edit.tap()
        let cards = ids.map { id in
            app.staticTexts.matching(NSPredicate(format: "identifier == %@", "home.card.template:\(id)")).firstMatch
        }
        let origins = cards.map { Int(($0.frame.minX / 4).rounded()) * 4 }
        XCTAssertEqual(Set(origins).count, 3, "expected three column origins, saw \(origins)")
        for card in cards {
            XCTAssertLessThanOrEqual(card.frame.maxX, scroll.frame.maxX + 1,
                                     "\(card.identifier) overflows the board")
        }
        for _ in 0..<3 { app.swipeDown() }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "three-columns"
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "three-columns-tree"
        tree.lifetime = .keepAlways
        add(tree)
        edit.tap()
        for id in ids {
            if let original = originals[id], original != "小" { choose(id, original) }
        }
        edit.tap()

    }
}
