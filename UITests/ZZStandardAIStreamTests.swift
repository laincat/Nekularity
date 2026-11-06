import Foundation
import XCTest

/// The standard-protocol screen shown streaming, through the real entry and a
/// real loopback HTTP server.
///
/// The fixture is `UITests/Fixtures/standard-ai/serve.py`, started before this
/// class (a UI test target cannot launch a process on the host; CI starts it in
/// the interface-test step). It must listen on 127.0.0.1:18796. Without it the
/// cases skip and say so: an absent server is not a broken screen. What the app
/// sent is read back over HTTP (`GET /requests`), not from a host file.
///
/// What each case proves:
/// - `testStreamedAnswer`: text appears while the answer is still being
///   written (the 「正在写…」 row), the finished answer is labelled 「流式」 and
///   reads as the four pieces the fixture sent, and the app sent `stream: true`
///   exactly once.
/// - `testStreamCutoff`: a stream that stops without the protocol's completion
///   marker is reported as an error, and the half answer is not kept as a
///   finished one.
///
/// Both cases restore what they change: the endpoint settings live in the
/// app's defaults and the key in its keychain, so a later run, or a person,
/// does not inherit a fixture URL.
final class ZZStandardAIStreamTests: XCTestCase {
    private let port: UInt16 = 18796
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Fixture

    private func fixtureEvents() -> [[String: Any]] {
        guard let url = URL(string: "http://127.0.0.1:\(port)/events"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list
    }

    private func requireFixture() throws {
        guard let url = URL(string: "http://127.0.0.1:\(port)/events"), (try? Data(contentsOf: url)) != nil else {
            throw XCTSkip("standard-AI fixture is not listening on 127.0.0.1:\(port); see UITests/Fixtures/standard-ai/README.md")
        }
    }

    /// The request bodies the fixture accepted, oldest first.
    private func requestBodies() -> [[String: Any]] {
        guard let url = URL(string: "http://127.0.0.1:\(port)/requests"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Reaching the screen

    private func settingsTab() -> XCUIElement {
        let inBar = app.tabBars.buttons["设置"].firstMatch
        return inBar.exists ? inBar : app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch
    }

    private func openStandardScreen() {
        let tab = settingsTab()
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no 设置 section")
        tab.tap()
        let ai = app.buttons["settings.ai"].firstMatch
        for _ in 0..<8 where !ai.isHittable { app.swipeUp() }
        XCTAssertTrue(ai.waitForExistence(timeout: 10), "no AI entry in 设置")
        ai.tap()
        let standard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "标准接口")).firstMatch
        XCTAssertTrue(standard.waitForExistence(timeout: 15), "no 标准接口 row on the AI list")
        standard.tap()
        XCTAssertTrue(app.navigationBars["标准接口"].waitForExistence(timeout: 15), "the standard screen did not open")
    }

    /// Picks OpenAI Chat, points it at `root` and stores the fixture key.
    ///
    /// Every case uses the same root, so the address field is written once per
    /// launch rather than rewritten between cases.
    private func configure(root: String) {
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "接口")).firstMatch
        if picker.waitForExistence(timeout: 5) {
            picker.tap()
            let chat = app.buttons["OpenAI Chat"].firstMatch
            if chat.waitForExistence(timeout: 5) { chat.tap() }
        }
        let address = app.textFields.element(boundBy: 0)
        XCTAssertTrue(address.waitForExistence(timeout: 10), "no address field")
        replace(address, with: root, where: "the endpoint URL")
        let model = app.textFields["模型名"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 10), "no model field")
        replace(model, with: "fixture-model", where: "the model name")
        let key = app.secureTextFields.firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 10), "no key field")
        // A secure field reads back as bullets, so the proof that the key was
        // stored is the 清除密钥 button, which only appears once one is loaded.
        tapEnd(key)
        key.typeText("fixture-key")
        let save = app.buttons["保存密钥"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no 保存密钥 button")
        save.tap()
        XCTAssertTrue(app.buttons["清除密钥"].firstMatch.waitForExistence(timeout: 10),
                      "the key was not stored: no 清除密钥 button appeared")
    }

    /// Taps at the far right of a field, which puts the caret after the text.
    ///
    /// Tapping the middle puts the caret where the finger landed: deletes then
    /// remove only what is left of it and typing inserts in the middle, which
    /// produced `http://127.0.0.1:18796/v1cutoff/v1` in an earlier run.
    private func tapEnd(_ field: XCUIElement) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    /// Replaces a field's text, then proves the text arrived: a case that fails
    /// here should say "the URL did not reach the field", not "no answer
    /// appeared" ten seconds later.
    private func replace(_ field: XCUIElement, with text: String, where note: String) {
        tapEnd(field)
        let current = field.value as? String ?? ""
        if !current.isEmpty, current != field.placeholderValue {
            // More deletes than characters: the reported value can be shorter
            // than what the field holds, and over-typing deletes nothing.
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 8))
        }
        if !text.isEmpty { field.typeText(text) }
        let landed = field.value as? String ?? ""
        let expected = text.isEmpty ? (field.placeholderValue ?? "") : text
        XCTAssertEqual(landed, expected, "\(note) did not reach the field")
    }

    private func ask(_ text: String) {
        let prompt = app.textFields["说点什么"].firstMatch
        for _ in 0..<8 where !prompt.isHittable { app.swipeUp() }
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "no prompt field")
        prompt.tap()
        prompt.typeText(text)
        let send = app.buttons["发送"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no 发送 button")
        send.tap()
    }

    /// Clears what the case stored, through the same screen a person uses.
    private func restore() {
        let clear = app.buttons["清除密钥"].firstMatch
        for _ in 0..<4 where !clear.isHittable { app.swipeDown() }
        if clear.waitForExistence(timeout: 5) { clear.tap() }
        let address = app.textFields.element(boundBy: 0)
        if address.waitForExistence(timeout: 5) { replace(address, with: "", where: "the endpoint URL") }
        let model = app.textFields["模型名"].firstMatch
        if model.waitForExistence(timeout: 5) { replace(model, with: "", where: "the model name") }
    }

    private func staticText(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: - Cases

    func testStreamedAnswer() throws {
        try requireFixture()
        let before = requestBodies().count
        app = XCUIApplication()
        app.launch()
        defer { restore(); app.terminate() }
        openStandardScreen()
        configure(root: "http://127.0.0.1:\(port)/v1")
        ask("说一段")

        // Mid-answer: the fixture sends a piece every 1.2 s, so the writing row
        // and the first pieces are on screen before the last one arrives.
        let writing = app.staticTexts["standardAI.streaming"].firstMatch
        XCTAssertTrue(writing.waitForExistence(timeout: 15), "no text appeared while the answer was being written")
        XCTAssertTrue(staticText(containing: "正在写").exists, "no 「正在写…」 row while streaming")
        capture("01-stream-halfway")

        // Finished: one answer, labelled as streamed, with every piece in order.
        let label = app.staticTexts["流式"].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 20), "the finished answer is not labelled 流式")
        XCTAssertFalse(app.staticTexts["整包返回"].exists, "a streamed answer was labelled 整包返回")
        XCTAssertTrue(staticText(containing: "流式第一段 第二段🐾").exists, "the finished text is not the four pieces in order")
        XCTAssertFalse(writing.exists, "the writing row stayed after the answer finished")
        capture("02-stream-finished")

        let bodies = Array(requestBodies().dropFirst(before))
        XCTAssertEqual(bodies.count, 1, "the fixture saw \(bodies.count) requests for one question")
        XCTAssertEqual(bodies.first?["stream"] as? Bool, true, "the app did not ask for a stream")
        XCTAssertEqual(bodies.first?["model"] as? String, "fixture-model")
    }

    func testStreamCutoff() throws {
        try requireFixture()
        app = XCUIApplication()
        app.launch()
        defer { restore(); app.terminate() }
        openStandardScreen()
        configure(root: "http://127.0.0.1:\(port)/v1")
        // The fixture cuts a stream when the prompt says 断流, so both cases use
        // one root and the address field is never rewritten mid-run.
        ask("断流：说一段")

        let failure = staticText(containing: "AI stream ended before completion")
        XCTAssertTrue(failure.waitForExistence(timeout: 20), "a stream cut short was not reported")
        capture("03-stream-cutoff")
        XCTAssertFalse(app.staticTexts["流式"].exists, "a cut-short stream was labelled 流式, as if complete")
        XCTAssertFalse(app.staticTexts["standardAI.streaming"].exists, "the writing row stayed after the failure")
        XCTAssertFalse(staticText(containing: "第一段").exists, "the half answer was kept as if it were finished")
        let cut = fixtureEvents().contains { ($0["event"] as? String) == "stream_cut" }
        XCTAssertTrue(cut, "the fixture never cut a stream, so this case proved nothing")
    }
}
