import XCTest

/// P1 evidence: the board at a real 3-column width.
final class ZZThreeColumnTests: XCTestCase {
    func testLandscapeBoardHasThreeColumns() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let discover = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'tab.discover'")).firstMatch
        XCTAssertTrue(discover.waitForExistence(timeout: 30), "no discover tab")
        discover.tap()
        let edit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'discover.edit'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "discovery did not draw")
        sleep(1)

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "no board scroll view")
        let width = scroll.frame.width
        XCTAssertGreaterThanOrEqual(width, 560, "content width is \(width), below the 3-column band")
        XCTAssertLessThan(width, 900, "content width is \(width), at or above the 4-column band")

        edit.tap()
        let ids = ["history", "favorites", "continueWatching"]
        var originals: [String: String] = [:]
        func choose(_ id: String, _ choice: String) {
            let control = app.buttons.matching(NSPredicate(format: "identifier == %@", "home.size.template:\(id)")).firstMatch
            if !control.isHittable { app.swipeUp() }
            XCTAssertTrue(control.waitForExistence(timeout: 10), "size control missing: \(id)")
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
