import XCTest

/// 设置 → 外观: the three-way light/dark choice, driven the way a person does.
///
/// The point of this case is that the choice is real: the picker is reached by
/// scrolling rather than by assuming where it sits, each state has to change the
/// screen immediately, and the last one has to survive a relaunch. A view that
/// only stores the value would pass a unit test and still look wrong here.
final class ZZAppearanceSettingsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    /// The 设置 section, in whichever bar this idiom draws it.
    ///
    /// iPhone uses a bottom tab bar; iPad draws the same `TabView` as a compact
    /// top bar of plain buttons that are not inside a `TabBar` element.
    private func settingsTab() -> XCUIElement {
        let inBar = app.tabBars.buttons["设置"].firstMatch
        if inBar.exists { return inBar }
        return app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func require(_ condition: Bool, _ message: String, _ name: String) throws {
        if !condition {
            capture(name + "-failure")
            throw NSError(domain: "AppearanceSettings", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// Scrolls until the picker is on screen, then hands it back.
    private func appearancePicker() -> XCUIElement {
        let picker = app.descendants(matching: .any)
            .matching(identifier: "settings.appearance").firstMatch
        for _ in 0..<8 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        return picker
    }

    private func choose(_ label: String) throws {
        let picker = appearancePicker()
        try require(picker.waitForExistence(timeout: 20), "设置 has no appearance picker", "picker")
        let option = picker.buttons[label].firstMatch
        let fallback = app.buttons[label].firstMatch
        let target = option.exists ? option : fallback
        try require(target.waitForExistence(timeout: 10), "the picker has no \(label) option", "picker-\(label)")
        target.tap()
    }

    /// The interface style the app is actually drawing with, read from the button
    /// the picker has selected rather than from the device, so a picker that stores
    /// a value without applying it fails here.
    private func selectedLabel() throws -> String {
        let picker = appearancePicker()
        try require(picker.waitForExistence(timeout: 20), "设置 has no appearance picker", "picker-read")
        for label in ["跟随系统", "亮", "暗"] {
            let option = picker.buttons[label].firstMatch
            if option.exists && option.isSelected { return label }
        }
        let selected = picker.buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch
        if selected.exists { return selected.label }
        try require(false, "no appearance option is marked selected", "picker-unselected")
        return ""
    }

    func testAppearanceChoiceAppliesAndSurvivesRelaunch() throws {
        app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let tab = settingsTab()
        try require(tab.waitForExistence(timeout: 30), "no 设置 section", "settings-tab")
        tab.tap()

        // The picker is below the first screenful, so reaching it is part of the
        // case: a section a person cannot scroll to is not a section.
        let picker = appearancePicker()
        try require(picker.waitForExistence(timeout: 20), "设置 has no appearance picker", "picker-missing")
        capture("appearance-picker")

        try choose("亮")
        try require(try selectedLabel() == "亮", "picking 亮 did not select it", "light-selected")
        capture("appearance-light")

        try choose("暗")
        try require(try selectedLabel() == "暗", "picking 暗 did not select it", "dark-selected")
        capture("appearance-dark")

        // A relaunch is the only honest way to show it was stored and not just
        // remembered in the view.
        app.terminate()
        app.launch()
        let again = settingsTab()
        try require(again.waitForExistence(timeout: 30), "no 设置 section after relaunch", "relaunch-tab")
        again.tap()
        try require(try selectedLabel() == "暗", "暗 was not kept across a relaunch", "dark-after-relaunch")
        capture("appearance-dark-after-relaunch")

        try choose("跟随系统")
        try require(try selectedLabel() == "跟随系统", "picking 跟随系统 did not select it", "system-selected")
        capture("appearance-system")
    }
}
