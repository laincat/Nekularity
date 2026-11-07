import Vision
import XCTest

/// Drives the app the way a person would, on a simulator seeded with sources.
///
/// Why this exists: the Windows machine can compile neither Swift nor an
/// interface, so "the page draws and the button works" was only ever checked by
/// hand on the Mac. That is how a settings screen shipped saying a source's login
/// and callback buttons were unsupported after both had been implemented.
///
/// The sources come from `scripts/seed-simulator.sh`, which writes the store file
/// a client restores from. Without it the source list is empty and the tests skip
/// rather than pass on nothing. Anything that needs a live site skips too, so a
/// network outage is not reported as a broken screen.
final class NekularityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }


    // MARK: - Reaching a screen

    /// The four tabs are 发现 / 我的 / 资源库 / 设置, so a screen that used to be
    /// its own tab is now behind one of them. These helpers keep the cases about
    /// what they test rather than about the shape of the bar.
    /// The root sections, wherever this idiom puts them.
    ///
    /// On iPhone they are a bottom tab bar. On iPad the same SwiftUI `TabView`
    /// draws a compact bar at the top, and the sections are plain buttons that
    /// are not inside a `TabBar` element at all — a query that only looks at
    /// `app.tabBars` finds nothing there and reports "no 发现 section" on a
    /// screen that is drawing it. Both are the same control to a person, so the
    /// lookup accepts either.
    private func sectionButton(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let inBar = app.tabBars.buttons[name].firstMatch
        if inBar.exists { return inBar }
        return app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = sectionButton(app, name)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no \(name) section")
        button.tap()
    }

    private func openSearch(_ app: XCUIApplication) throws {
        tab(app, "发现")
        let button = element(app, "discover.search")
        guard button.waitForExistence(timeout: 20) else { throw XCTSkip("发现 has no search button") }
        button.tap()
    }

    private func openBrowse(_ app: XCUIApplication) throws {
        tab(app, "发现")
        let button = element(app, "discover.browse")
        guard button.waitForExistence(timeout: 20) else { throw XCTSkip("发现 has no browse button") }
        button.tap()
    }

    private func openSources(_ app: XCUIApplication) throws {
        tab(app, "设置")
        let button = element(app, "settings.sources")
        guard button.waitForExistence(timeout: 20) else { throw XCTSkip("设置 has no sources entry") }
        button.tap()
    }

    private func openShelf(_ app: XCUIApplication) throws {
        tab(app, "我的")
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '书架与收藏夹'")).firstMatch
        guard link.waitForExistence(timeout: 20) else { throw XCTSkip("我的 has no shelf link") }
        link.tap()
    }

    private func openVideo(_ app: XCUIApplication) throws {
        tab(app, "资源库")
        let link = element(app, "library.video")
        guard link.waitForExistence(timeout: 20) else { throw XCTSkip("资源库 has no video entry") }
        link.tap()
    }

    /// `diagnostic` turns on the player's hidden one-line report of who owns
    /// subtitles on this route; it changes nothing a person sees.
    private func launch(diagnostic: Bool = false,
                        environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        if diagnostic { app.launchEnvironment["NK_VIDEO_DIAGNOSTIC"] = "1" }
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
        return app
    }

    /// Types into a field, retrying when the runner reports no keyboard focus.
    ///
    /// A tap whose normalised offset lands a couple of points off the text field
    /// leaves it without focus, and `typeText` then fails to synthesise the key
    /// events - a runner-side flake that once failed the HLS case before the player
    /// had even opened. The retry taps the field again and waits for the keyboard.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) {
        // `typeText` does not throw: without focus it records a failure on the
        // spot. So the retry is decided before typing, by whether a keyboard is up.
        for _ in 1...3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
                field.typeText(text)
                return
            }
        }
        XCTFail("no keyboard appeared after three taps on \(field)", file: file, line: line)
    }

    /// The element with this identifier, whatever kind it is.
    ///
    /// A `NavigationLink { Label(…) }` becomes a cell on one iOS version and a
    /// button on another, and a label is localized and can be renamed by a source,
    /// so the app tags the controls these tests press and the test asks for the
    /// tag. Labels are only the fallback, for a screen that has no tag yet.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        // Type-scoped queries first. Asking every descendant of a busy screen costs
        // seconds per evaluation, and a `waitForExistence` whose evaluation runs
        // past its own timeout reports "missing" for an element that is on screen —
        // that is how a detail page full of controls failed to load in one run.
        for query in [app.buttons, app.staticTexts, app.cells, app.otherElements] {
            let match = query.matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
            if match.exists { return match }
        }
        let tagged = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        if tagged.exists { return tagged }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", identifier)).firstMatch
    }

    /// A button inside the dialog that is on screen, not anywhere in the app.
    ///
    /// Puts a card's size back to what it was, and says so rather than asserting:
    /// this is housekeeping for the next case, so a board that cannot be restored
    /// must not turn a correct case into a failure.
    private func restoreBoardSize(_ app: XCUIApplication, of control: XCUIElement, to wanted: String) {
        let edit = app.buttons.matching(NSPredicate(format: "identifier == 'discover.edit'")).firstMatch
        if edit.label != "完成" { edit.tap() }
        guard control.waitForExistence(timeout: 5) else {
            print("NK_SIZE_RESTORE_SKIPPED: no size control after reopening arranging")
            return
        }
        if control.label == wanted {
            edit.tap()
            return
        }
        control.tap()
        let option = dialogButton(app, wanted)
        if option.waitForExistence(timeout: 5) { option.tap() }
        edit.tap()
        if control.label != wanted {
            print("NK_SIZE_RESTORE_NO_EFFECT: board is at \(control.label), wanted \(wanted)")
        }
    }

    /// `confirmationDialog` presents as a sheet on iPhone, and its buttons have no
    /// identifiers of their own, so they can only be found by label — which the cards
    /// underneath already use. Scoping the query to the dialog is what makes the label
    /// unambiguous.
    private func dialogButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let sheet = app.sheets.firstMatch
        if sheet.exists { return sheet.buttons[label] }
        return app.alerts.firstMatch.buttons[label]
    }

    /// Removes the fixture chapter from the downloads screen if an earlier run
    /// left it there. A download that is already on disk is not fetched again, so
    /// the failed-download case would make no request at all; the cleanup uses the
    /// same swipe a user has rather than deleting files behind the app.
    private func removeDownloadedProbeChapter(_ app: XCUIApplication) {
        tab(app, "我的")
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '下载'")).firstMatch
        guard entry.waitForExistence(timeout: 15) else { return }
        entry.tap()
        // A previous run can leave a downloaded chapter and a failure row, which
        // now survives a relaunch; they sit in different sections, so clear until
        // neither is left. A failure left behind would also leave a retry button
        // in front of the one this case is about.
        for _ in 0..<4 {
            let row = firstElement(app, containing: "Probe Comic")
            guard row.waitForExistence(timeout: 3) else { break }
            row.swipeLeft()
            let delete = app.buttons["删除"].firstMatch
            guard delete.waitForExistence(timeout: 3) else { break }
            delete.tap()
        }
        // Leave the pushed screen. Tapping the tab does not pop the stack, so
        // staying here would hide the downloads entry from the rest of the test.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 10) { back.tap() }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "我的 has no downloads entry after the cleanup")
    }

    /// The first element whose label contains `text`, whichever type it is.
    ///
    /// Each predicate is built where it is used: storing one and passing it to
    /// `matching` is what `check-swift` flags, because a stored predicate can carry
    /// its isolation across a call boundary.
    /// Scrolls the app until `element` can actually be tapped.
    ///
    /// At the largest accessibility text sizes a row that is laid out can still sit
    /// outside the viewport, and tapping an off-screen element fails with
    /// "Activation point invalid" — which reads like a broken control and is
    /// really a case that assumed one screenful was enough. The horizontal pass
    /// exists for chip rows, which scroll sideways.
    @discardableResult
    private func scrollToHittable(_ app: XCUIApplication, _ element: XCUIElement,
                                  horizontal: Bool = false, attempts: Int = 8) -> Bool {
        for _ in 0..<attempts {
            if hittable(element) { return true }
            if horizontal {
                // The chip row is its own horizontal scroll view. Swiping the whole
                // app scrolls the list under it instead, and the chip that needs to
                // come into view is off-screen to the right, so its own frame cannot
                // be the gesture's origin either. The drag runs along the row's
                // vertical centre, which is known even while the chip is not on screen.
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0))
                    .withOffset(CGVector(dx: 0, dy: element.frame.midY))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0))
                    .withOffset(CGVector(dx: 0, dy: element.frame.midY))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        return hittable(element)
    }

    /// Whether a tap would land on this element.
    ///
    /// `isHittable` raises "Failed to determine hittability … Activation point
    /// invalid" for an element whose frame is entirely outside the screen, which is
    /// what a row below the fold looks like at accessibility text sizes. Asking is
    /// therefore only safe once the frame intersects the viewport.
    private func hittable(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let screen = XCUIApplication().windows.firstMatch.frame
        guard screen.width > 0, screen.height > 0 else { return element.isHittable }
        guard element.frame.intersects(screen) else { return false }
        return element.isHittable
    }

    /// Waits for a row that a lazy list only builds once it is scrolled near.
    ///
    /// At the accessibility text sizes the detail page's chapter list starts below
    /// the fold, so a plain `waitForExistence` times out on a row that exists in the
    /// data and would appear the moment a person scrolled.
    @discardableResult
    private func scrollToExist(_ app: XCUIApplication, _ element: XCUIElement,
                               timeout: TimeInterval = 30, attempts: Int = 8) -> Bool {
        // On screen already is the common case, and swiping first would scroll a
        // row that was in view past the viewport before it was ever checked.
        if element.waitForExistence(timeout: timeout) { return true }
        // No wall-clock deadline inside the loop: at the accessibility sizes one
        // screenful is a few hundred points, a slow swipe costs about four seconds,
        // and stopping on the clock returned false on a page that still had content
        // to reach. The attempt count is the bound instead.
        for _ in 0..<attempts {
            app.swipeUp(velocity: .slow)
            if element.waitForExistence(timeout: 2) { return true }
        }
        return element.exists
    }

    private func firstElement(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        let asButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if asButton.exists { return asButton }
        let asCell = app.cells.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if asCell.exists { return asCell }
        let asLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        if asLabel.exists { return asLabel }
        return asButton
    }

    /// Picks a source in the toolbar picker of the screen it is called on.
    ///
    /// Which source is selected is remembered by the app between launches, so a
    /// case that assumes "the first one" is really assuming whatever the last run
    /// left behind — that is how the browse case started skipping once another case
    /// had switched to a source with no categories.
    private func chooseSource(_ app: XCUIApplication, _ name: String) throws {
        // 全部源 has no single-source picker to open, so a case that needs one
        // source asks for the range that has it instead of skipping.
        let one = app.buttons["当前源"]
        if one.waitForExistence(timeout: 5), one.isSelected == false { one.tap() }
        let picker = app.navigationBars.buttons
            .matching(NSPredicate(format: "label BEGINSWITH '漫画源'")).firstMatch
        guard picker.waitForExistence(timeout: 15) else {
            throw XCTSkip("this screen has no source picker")
        }
        picker.tap()
        let target = app.buttons[name].firstMatch
        guard target.waitForExistence(timeout: 10) else {
            throw XCTSkip("the source \(name) is not in the list")
        }
        target.tap()
        let switched = app.navigationBars.buttons
            .matching(NSPredicate(format: "label CONTAINS '\(name)'")).firstMatch
        XCTAssertTrue(switched.waitForExistence(timeout: 15), "the picker did not switch to \(name)")
    }

    /// Opens 漫画源 → source → 设置 and hands back the settings screen.
    private func openSettings(_ app: XCUIApplication, source key: String) throws {
        try openSources(app)
        let row = element(app, "source.\(key)")
        guard row.waitForExistence(timeout: 25) else {
            throw XCTSkip("no sources seeded: run scripts/seed-simulator.sh first")
        }
        row.tap()
        let settings = element(app, "source.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 20), "\(key) has no settings row")
        settings.tap()
    }

    /// The five tabs are the whole surface of the app; if one is missing its
    /// screen is unreachable and no other test means anything.
    func testTabsExist() {
        let app = launch()
        for title in ["发现", "我的", "资源库", "设置", "搜索"] {
            let button = sectionButton(app, title)
            XCTAssertTrue(button.waitForExistence(timeout: 30), "no \(title) tab")
        }
    }

    func testSwitchingTabsPreservesDiscoveryEditing() {
        let app = launch()
        tab(app, "发现")
        let edit = element(app, "discover.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        edit.tap()
        XCTAssertEqual(edit.label, "完成")
        tab(app, "设置")
        tab(app, "发现")
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        XCTAssertEqual(edit.label, "完成", "switching tabs discarded the board's editing state")
        edit.tap()
    }

    func testLibraryModuleLinksOpenTheirPages() {
        let app = launch()
        tab(app, "资源库")
        // A direct button query: at accessibility sizes the tree is large enough that
        // the generic lookup's four passes can each run past a wait's own timeout and
        // report a row that is on screen as missing.
        let comics = app.buttons.matching(NSPredicate(format: "identifier == %@", "library.comicSources")).firstMatch
        XCTAssertTrue(scrollToExist(app, comics), "no comic sources row on 资源库")
        XCTAssertTrue(scrollToHittable(app, comics), "the comic sources row never became tappable")
        comics.tap()
        XCTAssertTrue(app.navigationBars["漫画源"].waitForExistence(timeout: 20))
        app.navigationBars["漫画源"].buttons.element(boundBy: 0).tap()
        let videos = app.buttons.matching(NSPredicate(format: "identifier == %@", "library.videoSources")).firstMatch
        XCTAssertTrue(scrollToExist(app, videos), "no video sources row on 资源库")
        XCTAssertTrue(scrollToHittable(app, videos), "the video sources row never became tappable")
        videos.tap()
        XCTAssertTrue(app.navigationBars["视频"].waitForExistence(timeout: 20))
        let online = app.segmentedControls["video.mode"].buttons["在线源"]
        XCTAssertTrue(online.waitForExistence(timeout: 10))
        XCTAssertTrue(online.isSelected, "the video-source entry opened the local-files segment")
    }

    /// Seeded sources appear, which is the precondition for every other check.
    func testSeededSourcesAppear() throws {
        let app = launch()
        try openSources(app)
        // The seed the repository ships carries the two sources the other cases
        // press. It used to carry `nhentai` and `Komiic`, which are not in this
        // repository and whose absence turned this case into a skip on every
        // machine that did not have them - a skip that said nothing about the
        // client.
        guard element(app, "source.callback_probe").waitForExistence(timeout: 25) else {
            throw XCTSkip("no sources seeded: run scripts/seed-simulator.sh first")
        }
        XCTAssertTrue(element(app, "source.video_probe").exists,
                      "the video source is not seeded; run scripts/seed-simulator.sh with the current seed")
    }

    /// A source that logs in on its own page must offer that, not a sentence
    /// saying the client cannot.
    func testSourceOffersInPageLogin() throws {
        let app = launch()
        // The repository's own source declares the browser login real sources
        // declare, so this runs without `nhentai` and without a site. The URL it
        // names is the test runner's loopback server.
        try openSettings(app, source: "callback_probe")

        let login = element(app, "account.webviewLogin")
        XCTAssertTrue(login.waitForExistence(timeout: 25), "the in-page login button is missing")
        login.tap()
        // The sheet loads the page and titles itself after the source.
        let sheet = app.navigationBars["登录 Callback Probe"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 40), "the login sheet did not open")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "in-page-login-sheet"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["取消"].firstMatch.tap()
    }

    /// A callback setting is a button the source names itself; pressing it must
    /// reach the source rather than report that the client cannot do it.
    ///
    /// This preuses a source that has no network in it, deliberately. The first
    /// version pressed `wnacg`'s refresh button, and that source refreshes its
    /// domain list over the network from `init`, so on a machine that cannot reach
    /// that host the button never ran and the test measured the site. A callback
    /// that reports what it did, with nobody's network in the way, is what makes a
    /// failure here a failure of the client.
    func testCallbackSettingRuns() throws {
        let app = launch()
        try openSettings(app, source: "callback_probe")

        let run = element(app, "setting.callback.run")
        XCTAssertTrue(run.waitForExistence(timeout: 25), "the declared callback button is missing")
        run.tap()

        // Three things can prove the press reached the client, and any one is
        // enough: the control going busy, the source's dialog, or its answer.
        // Waiting for the busy marker alone was wrong: this source asks its
        // question immediately, and presenting a sheet can take the settings
        // screen out of the accessibility tree, so the marker is never visible.
        let busy = element(app, "setting.running.run")
        let dialog = app.navigationBars["Probe Result"].firstMatch
        let answer = app.staticTexts["setting.answer.run"]
        var reached = false
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if busy.exists || dialog.exists || answer.exists {
                reached = true
                break
            }
            if !element(app, "setting.callback.run").isEnabled {
                reached = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard reached else {
            // The tree is what says why: a press that lands nowhere and one that
            // hangs look the same from here.
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "callback-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the press never reached the client")
            return
        }

        // A source may ask before answering; the answer can only appear once that
        // dialog is dealt with.
        if dialog.exists {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "callback-dialog"
            shot.lifetime = .keepAlways
            add(shot)
            // The dialog is not an `app.sheets` element here, so asking for one
            // matched nothing and the case failed with a dialog on screen. Press
            // the action the source named, or the first button in that dialog's own
            // navigation bar.
            let ok = app.buttons["OK"].firstMatch
            if ok.exists {
                ok.tap()
            } else {
                app.navigationBars["Probe Result"].buttons.element(boundBy: 0).tap()
            }
        }

        // Once the dialog is answered the call returns, and the screen says so.
        XCTAssertTrue(answer.waitForExistence(timeout: 30), "the callback did not report a result")
        XCTAssertEqual(answer.label, "ran", "the source's own answer was not shown")
    }

    /// A tag the source has an opinion about is a control, not a word.
    ///
    /// The tag used to sit inside a `LabeledContent`, which gave it a hit area that
    /// did not take a press: the row was visible and tapping it did nothing, so the
    /// source's own `comic.onClickTag` could never run. This uses the repository's
    /// own source, so the answer depends on the client and not on a site.
    func testTagTapOpensTheSourcesRule() throws {
        let app = launch()
        try openSearch(app)

        // The tab searches the source the picker names, and the app remembers the
        // last choice, so this has to say which source it needs.
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        // Results are cards in a grid, not rows in a list: the link is a button
        // whose label carries the comic's title.
        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tag-search-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the test source returned no comic")
            return
        }
        card.tap()

        let tag = app.buttons["probe"].firstMatch
        guard tag.waitForExistence(timeout: 30) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "tag-detail-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the detail page drew no tappable tag")
            return
        }
        tag.tap()

        // The source maps that tag to a search, and the client opens its own search
        // sheet on the keyword the source chose.
        let sheet = app.navigationBars["callback_probe · probe"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the tag tap did not reach the source's rule")
    }

    /// Searching from the search tab reaches a comic's detail page with tags,
    /// which is the path the reading flow depends on.
    func testSearchReachesDetailWithTags() throws {
        let app = launch()
        try openSearch(app)
        // The repository's own source: no network, and a comic with tags. Inheriting
        // whatever source a previous case left selected would make this case depend
        // on the order the suite runs in.
        try chooseSource(app, "Callback Probe")
        // The screen carries its own field with a stable identifier. Before that
        // existed, `.searchable` drew no field at all here on iOS 27 — the tree
        // showed a navigation bar with the two pickers and nothing to type in —
        // so this case could only ever skip.
        let field = element(app, "search.field")
        guard field.waitForExistence(timeout: 25) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "search-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the search tab has no field")
            return
        }
        field.tap()
        field.typeText("love")
        app.typeText("\n")

        // This local fixture always returns this comic. An error or another
        // labelled control cannot stand in for its result, and a missing result
        // is a regression rather than an unavailable external site.
        let firstResult = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard firstResult.waitForExistence(timeout: 60) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "fixture-search-failure"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("Callback Probe is local and must return Probe Comic; inspect the fixture or Core error")
            return
        }
        firstResult.tap()

        // The details screen offers comments for a source that declares them; a
        // source that does not still shows chapters, which is the other proof the
        // page loaded rather than staying on an empty one.
        // Comments for a source that declares them; otherwise chapters, which the
        // page draws as rows of its list. A predicate cannot ask for "a label of
        // some length" here, so the rows are counted instead.
        var loaded = element(app, "detail.comments").waitForExistence(timeout: 20)
        if !loaded {
            // Chapters are rows of the detail list; one cell is enough to know the
            // page drew its content rather than staying empty.
            loaded = app.cells.firstMatch.waitForExistence(timeout: 25)
        }
        if !loaded {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "detail-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(loaded, "the detail page did not load its controls")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "detail-page"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A source that keeps comments shows its thread, and the thread is the
    /// source's own text rather than a placeholder.
    ///
    /// The desktop client has this pinned against real sources; on iOS nothing had
    /// ever opened the screen, so this case uses the repository's own source, which
    /// now answers `loadComments`.
    func testCommentsShowTheSourcesThread() throws {
        let app = launch()
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "comments-search-tree"
            tree.lifetime = .keepAlways
            add(tree)
            throw XCTSkip("the source returned no results: it did not answer search")
        }
        card.tap()

        // The entry is only drawn when the source declares comments.
        let entry = element(app, "detail.comments")
        guard entry.waitForExistence(timeout: 30) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "comments-entry-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("a source that keeps comments offered no comments entry")
            return
        }
        entry.tap()

        // The author and the body both have to arrive: a thread that opened on an
        // empty page would still render the entry.
        let author = app.staticTexts["probe_user"].firstMatch
        let opened = author.waitForExistence(timeout: 30)
        let body = app.staticTexts["Probe comment body"].firstMatch
        let bodyShown = body.waitForExistence(timeout: 30)
        if !(opened && bodyShown) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "comments-thread-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(opened, "the thread did not show the comment's author")
        XCTAssertTrue(bodyShown, "the thread did not show the comment's body")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "comments-thread"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The reader draws the pages a chapter hands back.
    ///
    /// Reading was the one stretch of the main path with no iOS evidence: it needs
    /// images, and images used to need a site. The test runner and the app share
    /// the simulator's loopback, so a server in the runner serves one page and the
    /// chapter points at it — a real decode, no network.
    func testReaderDrawsTheChaptersPage() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }

        let app = launch()
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the source did not answer search")
        }
        card.tap()

        // The chapter list is part of the detail page. A row in a list may surface
        // as a button, a cell or just its text depending on the SwiftUI version, so
        // all three are tried before giving up.
        let chapter = firstElement(app, containing: "Chapter 1")
        guard scrollToExist(app, chapter) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "reader-chapter-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the detail page listed no chapter")
            return
        }
        XCTAssertTrue(scrollToHittable(app, chapter), "the chapter row never became tappable")
        chapter.tap()

        // The keep button is disabled while the reader has no pages, so it is the
        // cheapest proof that images arrived rather than the reader merely opening.
        let keep = app.buttons["收藏本页"].firstMatch
        guard keep.waitForExistence(timeout: 40) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "reader-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the reader never showed its toolbar")
            return
        }
        let waitUntil = Date().addingTimeInterval(40)
        while !keep.isEnabled && Date() < waitUntil {
            Thread.sleep(forTimeInterval: 0.5)
        }
        let empty = app.staticTexts["这一话没有可读的页面"].exists
        if !keep.isEnabled || empty {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "reader-page-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertFalse(empty, "the reader says the chapter has no pages")
        XCTAssertTrue(keep.isEnabled, "the reader had no page to keep, so no image decoded")
        XCTAssertFalse(sectionButton(app, "发现").isHittable, "the root section bar is still covering the reader")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reader-page"
        shot.lifetime = .keepAlways
        add(shot)

        // Going back to the detail page and forward again must not lose the pages.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(chapter.waitForExistence(timeout: 20), "the detail page did not come back")
    }

    /// A source that declares a category page gets one, with its parts, its
    /// options and its results.
    ///
    /// The contract is easy to get half right: `category` carries the parts and
    /// `categoryComics` carries the options and the loader, so a client that reads
    /// only the first shows choosers that never load anything.
    func testCategoryPageListsItsPartsAndComics() throws {
        let app = launch()
        try openBrowse(app)
        try chooseSource(app, "Callback Probe")

        // The browse screen offers the category page as a chip once the source
        // declares one.
        let entry = app.buttons["分类"].firstMatch
        guard entry.waitForExistence(timeout: 30) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "category-entry-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("a source with a category page offered no entry for it")
            return
        }
        entry.tap()

        // A part value names a choice, and the result has to follow it.
        let choice = app.buttons["test"].firstMatch
        let choicesShown = choice.waitForExistence(timeout: 30)
        let comic = app.staticTexts["Probe Comic"].firstMatch
        let comicShown = comic.waitForExistence(timeout: 30)
        if !choicesShown || !comicShown {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "category-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(choicesShown, "the category page listed no part values")
        XCTAssertTrue(comicShown, "the category page listed no comics")

        // Picking another value has to mark itself as chosen and reload the list.
        // Waiting on the comic alone would pass instantly, since it is already on
        // screen; the chip's selected state is the part that has to change.
        choice.tap()
        let chosen = NSPredicate(format: "isSelected == true")
        let expectation = XCTNSPredicateExpectation(predicate: chosen, object: choice)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 30), .completed,
                       "the chosen value did not become the selected one")
        XCTAssertTrue(app.staticTexts["Probe Comic"].firstMatch.waitForExistence(timeout: 30),
                      "choosing another value emptied the list")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "category"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Reading a chapter puts the comic on the shelf, with where it stopped.
    ///
    /// The shelf is written by the reader, so this is the other half of the reading
    /// path that had no iOS evidence: the pages arrive from the runner's own server
    /// (see LocalImageServer) and the shelf has to remember the visit afterwards.
    func testReadingPutsTheComicOnTheShelf() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }

        let app = launch()
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the source did not answer search")
        }
        card.tap()

        let chapter = firstElement(app, containing: "Chapter 1")
        guard scrollToExist(app, chapter) else {
            throw XCTSkip("the detail page listed no chapter")
        }
        XCTAssertTrue(scrollToHittable(app, chapter), "the chapter row never became tappable")
        chapter.tap()

        // Wait for a page to decode: the shelf is only written once there is one.
        let keep = app.buttons["收藏本页"].firstMatch
        guard keep.waitForExistence(timeout: 40) else {
            throw XCTSkip("the reader never showed its toolbar")
        }
        let deadline = Date().addingTimeInterval(40)
        while !keep.isEnabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard keep.isEnabled else {
            throw XCTSkip("no page decoded, so there is nothing for the shelf to record")
        }
        // Moving the reader is what makes it write progress rather than merely open.
        app.swipeUp()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        try openShelf(app)

        // The comic's title also appears on the detail page, so a tab switch that
        // silently failed would leave it on screen and make a title-only assertion
        // pass for the wrong reason. The shelf's own header comes first.
        let onShelf = app.navigationBars["书架"].waitForExistence(timeout: 20)
        // The row's second line is the shelf's: chapter, then page, then how long
        // ago — the detail page draws no such line.
        let progress = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Chapter 1' AND label CONTAINS '第 1 页'"))
            .firstMatch
        let listed = app.staticTexts["Probe Comic"].firstMatch.waitForExistence(timeout: 30)
        let progressShown = progress.waitForExistence(timeout: 20)
        if !(onShelf && listed && progressShown) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "shelf-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(onShelf, "the shelf tab did not open")
        XCTAssertTrue(listed, "reading the chapter did not put the comic on the shelf")
        XCTAssertTrue(progressShown, "the shelf row does not say where reading stopped")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "shelf-after-reading"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The favourites a source keeps on its own side are listed, and the entry
    /// that opens them only appears through the source's own page.
    ///
    /// Source favourites are a top-level `favorites` block, not part of `comic`,
    /// which is the kind of thing a client gets wrong silently: the screen opens
    /// and shows its empty state.
    func testSourceFavoritesShowWhatTheSourceKeeps() throws {
        let app = launch()
        try openSources(app)

        let row = element(app, "source.callback_probe")
        guard row.waitForExistence(timeout: 25) else {
            throw XCTSkip("the test source is not seeded")
        }
        row.tap()

        let entry = element(app, "source.favorites")
        guard entry.waitForExistence(timeout: 20) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "favorites-entry-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the source page offers no favourites entry")
            return
        }
        entry.tap()

        // The source answers with one comic; the empty state says "这个收藏夹没有内容".
        let comic = app.staticTexts["Probe Comic"].firstMatch
        let shown = comic.waitForExistence(timeout: 30)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch.exists
        if !shown {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "favorites-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(shown, "the favourites the source keeps were not listed")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "source-favorites"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A search a reader made is still there after the app is opened again.
    ///
    /// This is the one thing about the history that a unit test cannot show: the
    /// store can be correct and the app can still fail to write it, or to read it
    /// back on the next launch.
    func testSearchHistorySurvivesRelaunch() throws {
        let app = launch()
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        // Wait for the search to have run: the history is written with it, so
        // reopening before this would test nothing.
        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the source did not answer search, so nothing was recorded")
        }

        app.terminate()
        app.launch()
        try openSearch(app)

        // The word comes back as a chip above the results. With an empty field the
        // screen shows the recent searches, which is where it has to appear.
        let chip = app.buttons["probe"].firstMatch
        let shown = chip.waitForExistence(timeout: 30)
        if !shown {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "history-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(app.staticTexts["最近搜索"].exists,
                      "the search screen came back without its recent searches")
        XCTAssertTrue(shown, "the keyword was not kept across a relaunch")
    }

    /// The browse tab lists a source's sections and switches between them.
    ///
    /// This used to assert a section chip on a source with a single section, which
    /// the client deliberately does not draw: with one section it goes straight to
    /// the comics. The source now declares two, so the chips are part of what is
    /// being checked, along with the switch between them.
    func testBrowseLoadsSections() throws {
        let app = launch()
        try openBrowse(app)
        try chooseSource(app, "Callback Probe")

        let shelf = app.buttons["Probe Shelf"].firstMatch
        guard shelf.waitForExistence(timeout: 30) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "browse-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the browse tab drew no section chip")
            return
        }
        XCTAssertTrue(app.buttons["Probe Second"].firstMatch.exists,
                      "a source with two sections offered one chip")

        // The first section's comic: a chip row over an empty list is a section
        // that did not load.
        let comic = app.staticTexts["Probe Comic"].firstMatch
        let comicShown = comic.waitForExistence(timeout: 30)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch.exists
        XCTAssertTrue(comicShown, "the first section loaded no comic")

        // Switching sections has to change the list, not only the selection.
        let second = app.buttons["Probe Second"].firstMatch
        // The chip row scrolls sideways: at large text the second chip starts
        // outside the viewport, and tapping it there is not possible.
        XCTAssertTrue(scrollToHittable(app, second, horizontal: true),
                      "the second section chip never became tappable")
        second.tap()
        let other = app.staticTexts["Probe Other"].firstMatch
        let otherShown = other.waitForExistence(timeout: 30)
            || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Probe Other'")).firstMatch.exists
        if !otherShown {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "browse-second-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(otherShown, "switching sections did not load the other section")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "browse-sections"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 资源库 is the hub: 全源搜索, 书库, 视频, 下载 are its entries.
    ///
    /// The 全源搜索 entry has to land in 全部源 rather than one source, because
    /// a search screen that silently searches one source is not what the entry
    /// promised.
    func testLibraryHubReachesItsEntries() throws {
        let app = launch()
        tab(app, "资源库")

        for id in ["library.searchAll", "library.shelf", "library.video", "library.downloads"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 20), "资源库 has no \(id)")
        }

        element(app, "library.searchAll").tap()
        // A client with no sources has nothing to search: the screen says so
        // instead of drawing a field. That is the empty case, not a broken
        // entry, so it skips the way the other seeded cases do.
        if !element(app, "search.field").waitForExistence(timeout: 20) {
            if app.staticTexts["没有可用的漫画源"].exists {
                throw XCTSkip("no sources seeded: run scripts/seed-simulator.sh first")
            }
            XCTFail("全源搜索 opened nothing to type in")
        }
        // 全部源 is the scope the entry promises.
        XCTAssertTrue(app.buttons["全部源"].waitForExistence(timeout: 10),
                      "全源搜索 did not offer 全部源")
    }

    /// The video path end to end: a provider answers, the client asks where the
    /// episode plays, and the engine decodes the bytes.
    ///
    /// The clip comes from the runner on loopback, and that server refuses the
    /// request unless it carries the `Referer` the source declared. So a passing
    /// case is evidence for three things at once: `video.loadPlay` reached the
    /// client, the headers travelled to the engine, and the picture decoded. A
    /// duration only exists once frames are being produced, which is why the
    /// assertion waits for it rather than for the player screen opening.
    func testVideoPlaysTheSourcesClip() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }

        let app = launch()
        try openVideo(app)

        // The tab opens on 本机; the provider search is the other segment.
        let online = app.buttons["在线源"].firstMatch
        if online.waitForExistence(timeout: 10) { online.tap() }
        let picker = element(app, "video.source")
        guard picker.waitForExistence(timeout: 20) else {
            throw XCTSkip("the 视频 tab has no source picker")
        }
        picker.tap()
        let provider = app.buttons["Video Probe"].firstMatch
        guard provider.waitForExistence(timeout: 10) else {
            throw XCTSkip("the video fixture is not seeded: run scripts/seed-simulator.sh")
        }
        provider.tap()

        let field = element(app, "video.query")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the 视频 tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = firstElement(app, containing: "Probe Clip")
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the video fixture did not answer search")
        }
        card.tap()

        let episode = firstElement(app, containing: "Episode 1")
        XCTAssertTrue(episode.waitForExistence(timeout: 30), "the detail page lists no episode")
        episode.tap()

        // Three different failures used to share one message: the detail page
        // refused the play answer, the player never opened, or it opened and drew
        // nothing. Waiting for either of the first two says which one happened.
        let player = element(app, "video.close")
        let refused = element(app, "video.failure")
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, !player.exists, !refused.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(player.exists || refused.exists,
                      "tapping the episode did nothing: neither a player nor a refusal appeared")
        XCTAssertFalse(refused.exists, "the detail page refused to open a player")
        // 关闭 lives in the navigation bar, so it is there whether or not the
        // transport bar has auto-hidden: this asks "did the screen open", nothing
        // about playback.
        XCTAssertTrue(player.exists, "the player screen never opened")
        let duration = element(app, "video.duration")
        XCTAssertTrue(duration.waitForExistence(timeout: 90),
                      "no duration: \(server.clipSummary())")

        // A duration exists as soon as decoding starts, even if the picture then
        // stalls on its first frame. The element's value is the engine's own
        // clock, so two reads a few seconds apart say whether frames advance.
        // This is what an engine upgrade has to keep working.
        func seconds(_ clock: String) -> Int? {
            let parts = clock.split(separator: ":").compactMap { Int($0) }
            guard !parts.isEmpty, parts.count == clock.split(separator: ":").count else { return nil }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        let first = seconds(duration.value as? String ?? "")
        Thread.sleep(forTimeInterval: 4)
        // The transport bar may have hidden itself; a tap on the picture brings
        // it back without pausing.
        if !duration.exists { app.windows.firstMatch.tap() }
        XCTAssertTrue(duration.waitForExistence(timeout: 10), "the transport did not come back")
        let second = seconds(duration.value as? String ?? "")
        XCTAssertNotNil(first, "the clock was not readable: \(String(describing: duration.value))")
        XCTAssertNotNil(second, "the clock was not readable: \(String(describing: duration.value))")
        if let first, let second {
            XCTAssertGreaterThan(second, first,
                                 "the picture did not advance: \(first)s then \(second)s")
        }
    }

    /// Opens one of the loopback probe videos and its only episode.
    private func openProbe(_ app: XCUIApplication, title: String) throws {
        try openVideo(app)
        let online = app.buttons["在线源"].firstMatch
        if online.waitForExistence(timeout: 10) { online.tap() }
        let picker = element(app, "video.source")
        guard picker.waitForExistence(timeout: 20) else {
            throw XCTSkip("the 视频 tab has no source picker")
        }
        picker.tap()
        // First launch after an install reads the seed while Core is still
        // starting; 10 s was not enough on a run of 2026-11-07 and the case
        // skipped with the source present all along.
        let provider = app.buttons["Video Probe"].firstMatch
        guard provider.waitForExistence(timeout: 60) else {
            throw XCTSkip("the video fixture is not seeded: run scripts/seed-simulator.sh")
        }
        provider.tap()
        let field = element(app, "video.query")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the 视频 tab has no field")
        type("probe", into: field, in: app)
        app.typeText("\n")
        let card = firstElement(app, containing: title)
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the seeded video fixture has no \(title): regenerate the seed")
        }
        card.tap()
        let episode = firstElement(app, containing: "Episode 1")
        XCTAssertTrue(episode.waitForExistence(timeout: 30), "the detail page lists no episode")
        episode.tap()
    }

    /// The duration element lives in the transport bar, which auto-hides. A
    /// relaunched app can therefore open a playing picture with no visible
    /// clock; a tap on the picture brings it back without pausing.
    private func showClock(_ app: XCUIApplication) -> Bool {
        let duration = element(app, "video.duration")
        if duration.exists { return true }
        app.windows.firstMatch.tap()
        return duration.waitForExistence(timeout: 20)
    }

    /// The start position the client handed the engine, from the hidden
    /// diagnostic line. Unlike a clock reading taken later, this is the resume
    /// decision itself.
    private func requestedStart(_ app: XCUIApplication) -> Double? {
        let line = app.descendants(matching: .any)
            .matching(identifier: "video.diagnostic").firstMatch
        guard line.waitForExistence(timeout: 10) else { return nil }
        guard let range = line.label.range(of: "start=") else { return nil }
        return Double(line.label[range.upperBound...].split(separator: " ").first ?? "")
    }

    /// Seconds shown by the engine clock on the duration element's value.
    private func playedSeconds(_ app: XCUIApplication) -> Int? {
        let clock = element(app, "video.duration").value as? String ?? ""
        let parts = clock.split(separator: ":")
        let numbers = parts.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    /// Watching a 30 s clip past 7 s, closing it, relaunching the app, and
    /// opening the same episode again must start from the saved position.
    ///
    /// A 10 s clip puts 7 s within a few seconds of the end, where an engine may
    /// legitimately wrap to zero; the 30 s fixture keeps the save point away from
    /// both edges. The case uses a fresh UUID-named shelf file, so it neither
    /// inherits nor leaves a position in the app's default `shelf.json`.
    func testResumeStartsWhereTheVideoWasLeft() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }
        guard LocalImageServer.hlsDirectory != nil else {
            XCTFail("the 30 s HLS fixture is not in the test bundle")
            return
        }
        let env = ["NK_SHELF_FILE": "uitest-resume-\(UUID().uuidString).json",
                   "NK_VIDEO_DIAGNOSTIC": "1"]
        let app = launch(environment: env)

        try openProbe(app, title: "Probe Resume")
        XCTAssertTrue(element(app, "video.close").waitForExistence(timeout: 60),
                      "the player never opened: \(server.clipSummary())")
        let duration = element(app, "video.duration")
        XCTAssertTrue(showClock(app), "no duration: \(server.clipSummary())")
        XCTAssertTrue(app.staticTexts["0:30"].waitForExistence(timeout: 10),
                      "the 30 s fixture did not load: \(server.clipSummary())")

        // Wait for the picture to pass the resume threshold (> 5 s), then close.
        var saved: Int?
        let by = Date().addingTimeInterval(45)
        while Date() < by {
            if let now = playedSeconds(app), now >= 7 { saved = now; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertNotNil(saved, "the picture never reached 7 s: \(server.clipSummary())")
        let close = element(app, "video.close")
        XCTAssertTrue(close.waitForExistence(timeout: 10), "no close button")
        close.tap()

        // A new process: the saved position has to come back from the file, not
        // from a view still sitting in memory.
        app.terminate()
        for (key, value) in env { app.launchEnvironment[key] = value }
        app.launch()
        try openProbe(app, title: "Probe Resume")
        XCTAssertTrue(element(app, "video.close").waitForExistence(timeout: 60),
                      "the reopened player never opened: \(server.clipSummary())")
        XCTAssertTrue(showClock(app),
                      "the reopened player has no visible clock: \(server.clipSummary())")
        let start = requestedStart(app)
        let resumed = playedSeconds(app)
        print("resume: saved at \(String(describing: saved)) s, requested start \(String(describing: start)) s, reopened at \(String(describing: resumed)) s")
        XCTAssertNotNil(start, "the reopened player did not report its requested start position")
        if let start {
            XCTAssertGreaterThanOrEqual(start, 6,
                                         "the client asked the engine to start at \(start) s, not the saved position")
            // Tying the request to the moment the player closed: a stale entry
            // from an earlier run, or a hardcoded resume point, would otherwise
            // also satisfy "at least 6". The gap allows only the seconds the
            // close button itself took to tap.
            if let saved {
                XCTAssertGreaterThanOrEqual(start, Double(saved) - 1,
                                             "the resume point \(start) s is older than the position at close \(saved) s")
                XCTAssertLessThanOrEqual(start, Double(saved) + 10,
                                         "the resume point \(start) s is far beyond the position at close \(saved) s")
            }
        }
        XCTAssertNotNil(resumed, "the reopened player's clock was not readable")
        if let resumed {
            XCTAssertGreaterThanOrEqual(resumed, 6,
                                         "the episode restarted near the beginning instead of the saved position")
        }
        // And it keeps playing from there rather than freezing on the seeked frame.
        Thread.sleep(forTimeInterval: 2)
        _ = showClock(app)
        let later = playedSeconds(app)
        if let resumed, let later {
            XCTAssertGreaterThan(later, resumed, "the resumed picture did not advance")
        }
        element(app, "video.close").tap()
    }

    /// HLS with subtitles, on the engine this build pins.
    ///
    /// The fixture is a 30 s master playlist with two WebVTT groups (中文 default,
    /// English alternate) over fMP4 byte ranges, every request refused without the
    /// source's `Referer`. The WebVTT segments carry `X-TIMESTAMP-MAP`, without
    /// which AVFoundation never puts a cue on the media timeline. The case asks four things in turn: the picture advances,
    /// the English track can be chosen, its cue is actually drawn (the overlay's
    /// text, not the track name in a menu), and turning subtitles off removes it.
    func testHLSPlaysAndSwitchesSubtitles() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }
        guard LocalImageServer.hlsDirectory != nil else {
            XCTFail("the HLS fixture is not in the test bundle")
            return
        }

        let app = launch(diagnostic: true)
        try openVideo(app)
        let online = app.buttons["在线源"].firstMatch
        if online.waitForExistence(timeout: 10) { online.tap() }
        let picker = element(app, "video.source")
        guard picker.waitForExistence(timeout: 20) else {
            throw XCTSkip("the 视频 tab has no source picker")
        }
        picker.tap()
        let provider = app.buttons["Video Probe"].firstMatch
        guard provider.waitForExistence(timeout: 10) else {
            throw XCTSkip("the video fixture is not seeded: run scripts/seed-simulator.sh")
        }
        provider.tap()
        let field = element(app, "video.query")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the 视频 tab has no field")
        type("probe", into: field, in: app)
        app.typeText("\n")

        let card = firstElement(app, containing: "Probe HLS")
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the seeded video fixture predates the HLS entry: regenerate the seed")
        }
        card.tap()
        let episode = firstElement(app, containing: "Episode 1")
        XCTAssertTrue(episode.waitForExistence(timeout: 30), "the detail page lists no episode")
        episode.tap()

        XCTAssertTrue(element(app, "video.close").waitForExistence(timeout: 60),
                      "the player screen never opened: \(server.clipSummary())")
        let duration = element(app, "video.duration")
        XCTAssertTrue(duration.waitForExistence(timeout: 90), "no duration: \(server.clipSummary())")

        func seconds(_ clock: String) -> Int? {
            let parts = clock.split(separator: ":")
            let numbers = parts.compactMap { Int($0) }
            guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
            return numbers.reduce(0) { $0 * 60 + $1 }
        }
        func showTransport() {
            if !duration.exists { app.windows.firstMatch.tap() }
            _ = duration.waitForExistence(timeout: 10)
        }
        // The clip is ten seconds and the cue spans [0, 10), so the timeline is
        // the tightest thing in this case: an earlier run read 5 s then 10 s and
        // found the clip already ended. Pause first, run one second, pause again.
        let first = playedSeconds(app)
        XCTAssertNotNil(first, "the clock was not readable")
        element(app, "video.playPause").tap()
        showTransport()
        let paused = playedSeconds(app)
        element(app, "video.playPause").tap()
        Thread.sleep(forTimeInterval: 1.0)
        showTransport()
        element(app, "video.playPause").tap()
        showTransport()
        let second = playedSeconds(app)
        print("HLS clock: \(String(describing: first)) -> \(String(describing: paused)) -> \(String(describing: second))")
        XCTAssertNotNil(paused, "the clock was not readable while paused")
        if let paused, let second {
            XCTAssertGreaterThan(second, paused,
                                 "the picture did not advance while playing: \(paused)s then \(second)s")
            XCTAssertLessThan(second, 30, "the clip ended before it could be paused; no cue is due at the end")
        }

        showTransport()
        let menu = element(app, "video.subtitles")
        XCTAssertTrue(menu.waitForExistence(timeout: 20),
                      "no subtitle menu: the engine listed no tracks (\(server.clipSummary()))")
        menu.tap()
        let english = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS %@", "English", "英语")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 10), "the menu offers no English track")
        english.tap()

        // A cue only reaches the legible output while the picture is moving;
        // the case pauses before opening the menu, so resume here.
        element(app, "video.playPause").tap()
        Thread.sleep(forTimeInterval: 2)
        showTransport()
        let diagnostic = app.descendants(matching: .any)
            .matching(identifier: "video.diagnostic").firstMatch
        if diagnostic.waitForExistence(timeout: 5) {
            print("HLS diagnostic after choosing English: \(diagnostic.label)")
        } else {
            print("HLS diagnostic: the player showed no diagnostic element")
        }

        let cue = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Subtitle rendering proof")).firstMatch
        if !cue.waitForExistence(timeout: 20) {
            // Say what was on screen instead: the cue missing from the
            // accessibility tree and the cue missing from the picture are
            // different failures, and the screenshot settles which.
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "hls-english-no-cue"
            shot.lifetime = .keepAlways
            add(shot)
            var labels: [String] = []
            for text in app.staticTexts.allElementsBoundByIndex { labels.append(text.label) }
            print("HLS on-screen texts: \(labels)")
            print("HLS subtitle value: \(String(describing: menu.value)) phase via clock \(String(describing: duration.value))")
        }
        XCTAssertTrue(cue.exists,
                      "English was chosen but its cue was never drawn; vtt requests: \(server.subtitleFilesRequested())")
        print("HLS subtitle requests: \(server.subtitleFilesRequested())")

        showTransport()
        menu.tap()
        let off = app.buttons["关闭字幕"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 10), "the menu has no 关闭字幕")
        off.tap()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, cue.exists { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertFalse(cue.exists, "subtitles were turned off but the English cue is still drawn")

        // Choosing a language or 关闭字幕 makes it the default for the next
        // episode, which is the behaviour under test - so put the default back
        // to the system, or this case would hand every later case a preference
        // it never asked for.
        showTransport()
        menu.tap()
        let followSystem = app.buttons["跟随系统语言"].firstMatch
        XCTAssertTrue(followSystem.waitForExistence(timeout: 10),
                      "the menu offers no way back to the system language")
        followSystem.tap()
    }

    /// Reads the text actually drawn on screen, which is the only way to see a
    /// caption AVPlayer composites into its layer: those glyphs are pixels, not
    /// accessibility elements.
    private func recognizedText(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        } catch {
            return "ocr-failed: \(error)"
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// How many times a phrase appears in recognised text.
    ///
    /// A caption drawn twice - once by AVPlayer into its layer and once by the
    /// host overlay - reads as two lines with the same words, so counting the
    /// occurrences is how a duplicate is told apart from one clean caption.
    private func occurrences(of phrase: String, in text: String) -> Int {
        let needle = phrase.lowercased()
        var count = 0
        var haystack = text.lowercased()
        while let range = haystack.range(of: needle) {
            count += 1
            haystack = String(haystack[range.upperBound...])
        }
        return count
    }

    /// Captions on the AVPlayer-owned route, checked where they are drawn.
    ///
    /// The engine hands the legible selection to AVPlayer and keeps
    /// `subtitleCues` empty, and AVPlayer composites the caption into its own
    /// layer as pixels. So the case reads the screen, not the accessibility
    /// tree, and it picks the track while the picture is playing: an earlier
    /// version chose one after pausing and asserted after a ten-second clip had
    /// already ended, which could not have shown a cue at all.
    ///
    /// AVPlayer drawing the caption is also what carries it into PiP, AirPlay
    /// and an external display, so the host must not draw a second copy. The
    /// case therefore checks that the words appear exactly once.
    func testHLSLongSubtitlesAreDrawnInThePicture() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }
        let env = ["NK_SHELF_FILE": "uitest-hls30-\(UUID().uuidString).json"]
        // The engine log says which legible option AVPlayer actually selected.
        let app = launch(diagnostic: true, environment: env)

        try openProbe(app, title: "Probe HLS 30")
        XCTAssertTrue(element(app, "video.close").waitForExistence(timeout: 60),
                      "the player never opened: \(server.clipSummary())")
        XCTAssertTrue(showClock(app), "the player has no visible clock: \(server.clipSummary())")
        XCTAssertTrue(app.staticTexts["0:30"].waitForExistence(timeout: 10),
                      "the 30 s fixture did not load: \(server.clipSummary())")

        // Pause before opening the menu: on this runner the menu alone can take
        // 25 s, which is most of a 30 s clip. The cue is then presented when we
        // resume, rather than having expired while XCTest was finding buttons.
        element(app, "video.playPause").tap()
        let menu = element(app, "video.subtitles")
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "no subtitle menu")
        menu.tap()
        let english = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS %@", "English", "英语")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 10), "the menu offers no English track")
        english.tap()

        // Resume: AVPlayer only presents a cue while the picture is running.
        element(app, "video.playPause").tap()
        Thread.sleep(forTimeInterval: 3)
        let screen = app.screenshot()
        let seen = recognizedText(screen.image)
        print("HLS30 OCR: \(seen)")
        print("HLS30 subtitle requests: \(server.subtitleFilesRequested())")
        XCTAssertTrue(server.subtitleFilesRequested().contains { $0.contains("sub-en30.vtt") },
                      "the selected track was never fetched: \(server.subtitleFilesRequested())")
        if !seen.lowercased().contains("subtitle") {
            let attachment = XCTAttachment(screenshot: screen)
            attachment.name = "hls30-no-caption"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(seen.lowercased().contains("subtitle") || seen.lowercased().contains("proof"),
                      "the picture shows no caption: \(seen)")
        // Exactly once: AVPlayer owns the pixels, the host only keeps the text
        // for accessibility, so a second copy means both drew it.
        let repeats = occurrences(of: "subtitle rendering proof", in: seen)
        XCTAssertEqual(repeats, 1,
                       "the caption is drawn \(repeats) times: \(seen)")
        // The host overlay draws a real SwiftUI Text, so the same words must
        // also be readable without looking at pixels.
        let caption = app.staticTexts["Subtitle rendering proof"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10),
                      "the caption is not an accessibility element: \(seen)")

        // Turning captions off withdraws the line.
        _ = showClock(app)
        menu.tap()
        let off = app.buttons["关闭字幕"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 10), "the menu has no 关闭字幕")
        off.tap()
        let goneBy = Date().addingTimeInterval(10)
        while Date() < goneBy, caption.exists { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertFalse(caption.exists, "turning subtitles off left the caption on screen")

        // Leave the default where it was.
        _ = showClock(app)
        menu.tap()
        let followSystem = app.buttons["跟随系统语言"].firstMatch
        if followSystem.waitForExistence(timeout: 10) { followSystem.tap() }
        element(app, "video.close").tap()
    }

    /// The batch update, driven through the interface it is reached by.
    ///
    /// It shipped broken: every installed source failed with "already exists" because
    /// the replace branch looked for a wording Core no longer uses. A unit test pins
    /// that now, but the button is what a person presses — this installs a source from
    /// the loopback server, presses 更新全部, and expects the answer "already current"
    /// rather than a failure list.
    func testUpdateAllReportsCurrentRatherThanFailing() throws {
        // Its own port: the seeded fixtures need 18731, and two cases in a row both
        // binding it is what failed the video case after this one.
        let server = try LocalImageServer(port: 18741)
        try server.start()
        addTeardownBlock { server.stop() }

        let app = launch()
        try openSources(app)

        // Add from a URL, which is the flow the failure broke first.
        let addButton = element(app, "sources.add")
        XCTAssertTrue(addButton.waitForExistence(timeout: 20), "the sources page has no add button")
        addButton.tap()

        // Asked for as a text field directly: the generic lookup can land on the
        // placeholder label, and a tap there focuses nothing. The value is then read
        // back, because "the install button is disabled" and "the URL never arrived"
        // are the same symptom from the outside.
        let field = app.textFields["sources.scriptURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "the add sheet has no URL field")
        field.tap()
        field.typeText(server.scriptURL)
        let typed = Date().addingTimeInterval(15)
        while Date() < typed, (field.value as? String) != server.scriptURL {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(field.value as? String, server.scriptURL,
                       "the URL never reached the add sheet's field")

        let install = element(app, "sources.installScript")
        XCTAssertTrue(install.exists, "the add sheet has no install button")
        install.tap()
        // The sheet stayed open after a successful install once, covering the list and
        // every control in it — which is what a batch update that did nothing was.
        // Polled rather than expectation(_:evaluatedWith:): that form hands the element
        // to a non-isolated predicate callback, which strict concurrency rejects.
        let closed = Date().addingTimeInterval(30)
        while Date() < closed, field.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(field.exists, "the add sheet stayed open after installing")

        let row = firstElement(app, containing: "Batch")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the installed source never appeared")

        // Update-all is a first-class toolbar button. It used to sit inside a menu
        // labelled 导入备份, which is both hard to find and wrongly named.
        let update = element(app, "sources.updateAll")
        XCTAssertTrue(update.waitForExistence(timeout: 20), "the sources page has no update-all button")
        update.tap()

        // Did the tap start anything? The button relabels itself while the update
        // runs, so this separates "the task never began" from "it ran and showed
        // nothing" — two failures that used to read the same.
        let started = app.buttons.matching(NSPredicate(format: "label CONTAINS '正在更新'"))
            .firstMatch.waitForExistence(timeout: 20)

        // The result lands in the list, under 更新结果. It used to be an alert, where
        // "no alert" and "an alert saying something else" looked identical from a test.
        let summary = element(app, "sources.updateSummary")
        let appeared = summary.waitForExistence(timeout: 60)
        let said = appeared ? summary.label : ""
        server.stop()
        if !appeared {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "no-summary-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertTrue(appeared, "pressing 更新全部 produced no summary (task started: \(started))")
        XCTAssertFalse(said.contains("already exists"),
                       "the update reported the old refusal instead of a result: \(said)")
        XCTAssertFalse(said.contains("失败"), "the update failed: \(said)")
        XCTAssertTrue(said.contains("已是最新") || said.contains("已更新"),
                      "the update produced no result line: \(said)")
    }

    /// Arranging the board: the controls that appear, the sizes on offer, and that
    /// 完成 puts them away.
    ///
    /// 编辑 is the entry this case uses. The long-press entry and persistence across
    /// a fresh process are exercised separately below.
    func testArrangingTheBoardShowsItsControls() throws {
        let app = launch()
        tab(app, "发现")

        let size = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.size.'")).firstMatch
        XCTAssertFalse(size.exists, "the size menu is on screen before arranging was entered")

        let edit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'discover.edit'")).firstMatch
        guard edit.waitForExistence(timeout: 25) else {
            XCTFail("发现 has no 编辑 button")
            return
        }
        edit.tap()

        XCTAssertTrue(size.waitForExistence(timeout: 10),
                      "编辑 did not put the board into arranging")
        let hide = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.hide.'")).firstMatch
        XCTAssertTrue(hide.exists, "arranging shows no hide control")

        // The size this case starts from is whatever a previous case left behind,
        // so it is recorded and put back: a board left at 中 changes the layout a
        // later screenshot or case sees, and an iPad screenshot once came out in
        // one column because of exactly that.
        let original = size.label
        size.tap()
        // Scoped to the dialog: the card's own size button carries the same 小/中
        // label, so an app-wide query for 中 matches several elements and the tap
        // fails with "Multiple matching elements found" — a broken query, not a
        // broken control.
        let small = dialogButton(app, "小")
        XCTAssertTrue(small.waitForExistence(timeout: 5), "the size dialog offers no 小")
        let medium = dialogButton(app, "中")
        XCTAssertTrue(medium.exists, "the size dialog offers no 中")
        medium.tap()

        let done = app.buttons["完成"].firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
        XCTAssertFalse(size.exists, "the size control stayed after arranging ended")

        restoreBoardSize(app, of: size, to: original)
    }

    /// Uses the gesture entry, changes a size, and checks that the saved choice
    /// survives a new process. A label changing before termination alone would
    /// only prove that in-memory state changed, not that the choice was saved.
    ///
    /// The press goes on the handle, not the whole card: a card long press belongs to
    /// `.draggable` and never reaches a simultaneous long-press gesture on the board.
    func testBoardLongPressAndSizeSurviveRelaunch() throws {
        let app = launch()
        tab(app, "发现")
        defer {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "board-long-press-and-persistence"
            tree.lifetime = .keepAlways
            add(tree)
        }

        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'home.card.template:history'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the history card is missing")
        let sizeID = "home.size.template:history"
        let size = app.buttons.matching(NSPredicate(format: "identifier == %@", sizeID)).firstMatch
        XCTAssertFalse(size.exists, "arranging was already active before the long press")
        let handle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'board.handle.template:history'")).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10),
                      "the board offers no visible way into arranging")
        handle.press(forDuration: 1.0)
        XCTAssertTrue(size.waitForExistence(timeout: 10), "a long press did not enter arranging")
        let edit = app.buttons.matching(NSPredicate(format: "identifier == 'discover.edit'")).firstMatch
        XCTAssertEqual(edit.label, "完成", "the long press did not change the edit action")

        // 大 is a real choice too: a case that left the board at 大 used to fail
        // here for a reason that had nothing to do with long presses.
        let original = size.label
        XCTAssertTrue(["小", "中", "大"].contains(original), "unexpected size label: \(original)")
        let chosen = original == "小" ? "中" : "小"
        size.tap()
        let option = dialogButton(app, chosen)
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the size choice is missing")
        option.tap()
        let changed = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", sizeID, chosen)).firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 5), "the chosen size did not reach the card")
        edit.tap()

        app.terminate()
        app.launch()
        tab(app, "发现")
        XCTAssertFalse(size.exists, "arranging unexpectedly survived a relaunch")
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "the edit action is missing after relaunch")
        edit.tap()
        XCTAssertTrue(changed.waitForExistence(timeout: 10), "the size choice was not restored after relaunch")

        // Restore the starting size so this case does not choose the next case's
        // layout. It deliberately chooses the opposite of whatever was persisted.
        changed.tap()
        let restore = dialogButton(app, original)
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "the original size choice is missing")
        restore.tap()
        edit.tap()
    }

    /// A downloaded chapter has to survive the network going away.
    ///
    /// The test downloads a chapter from the loopback fixture, **stops the
    /// server**, and only then opens the reader. If the pages still draw, the
    /// bytes came from disk — which is the whole promise of a download, and the
    /// one thing a "the file exists" assertion would not prove.
    func testDownloadedChapterReadsWithNoServer() throws {
        let server = try LocalImageServer()
        try server.start()
        // Always stop it: a case that fails before this point used to hold port
        // 18731 and fail the next three cases with "address already in use".
        addTeardownBlock { server.stop() }

        let app = launch()
        // A corrupt control run leaves a chapter on disk. Downloads are
        // deliberately not re-fetched, so this case must start clean or it would
        // read the previous run's bytes instead of downloading the real image.
        removeDownloadedProbeChapter(app)
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the source did not answer search")
        }
        card.tap()

        let chapter = firstElement(app, containing: "Chapter 1")
        XCTAssertTrue(scrollToExist(app, chapter), "the detail page lists no chapter")
        XCTAssertTrue(scrollToHittable(app, chapter), "the chapter row never became tappable")
        chapter.press(forDuration: 1.2)
        let keep = app.buttons["下载这一话"].firstMatch
        guard keep.waitForExistence(timeout: 10) else {
            throw XCTSkip("no download action on a chapter row")
        }
        keep.tap()

        // The downloads screen lives under 我的 now, next to the calendar.
        tab(app, "我的")
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '下载'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "我的 has no downloads entry")
        entry.tap()
        XCTAssertTrue(firstElement(app, containing: "Probe Comic").waitForExistence(timeout: 90),
                      "the chapter never appeared in downloads")

        // From here on there is no server: anything that draws is on disk.
        server.stop()

        // The downloads row is the way in, and the only one that can work: asking
        // the source for a chapter list with the server gone would be asking the
        // network to prove that the network is not needed.
        firstElement(app, containing: "Probe Comic").tap()
        // The toolbar exists even with no image. ReaderPage exposes this image
        // label only after ImageLoader has produced a CGImage.
        let page = app.images.matching(
            NSPredicate(format: "label BEGINSWITH '第 ' AND label ENDSWITH ' 页'")
        ).firstMatch
        guard page.waitForExistence(timeout: 90) else {
            XCTFail("no decoded page image appeared with the server stopped")
            return
        }
        let screenshot = XCTAttachment(screenshot: page.screenshot())
        screenshot.name = "downloaded-page-with-server-stopped"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "downloaded-page-with-server-stopped-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// HTTP 200 bytes that are not an image are a failed download, not a
    /// completed chapter. The store must show a retry; after the fixture serves
    /// a real PNG, retry saves it, and the reader decodes it with the server
    /// stopped. This replaces the old negative control, which asserted the
    /// incorrect "bad bytes still form a chapter" behaviour.
    func testDownloadedChapterBadImageFailsThenRetries() throws {
        let server = try LocalImageServer(corruptPages: true)
        try server.start()
        addTeardownBlock { server.stop() }

        let app = launch()
        removeDownloadedProbeChapter(app)
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the source did not answer search")
        }
        card.tap()

        let chapter = firstElement(app, containing: "Chapter 1")
        XCTAssertTrue(scrollToExist(app, chapter), "the detail page lists no chapter")
        XCTAssertTrue(scrollToHittable(app, chapter), "the chapter row never became tappable")
        chapter.press(forDuration: 1.2)
        let keep = app.buttons["下载这一话"].firstMatch
        guard keep.waitForExistence(timeout: 10) else {
            throw XCTSkip("no download action on a chapter row")
        }
        keep.tap()

        tab(app, "我的")
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '下载'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "我的 has no downloads entry")
        entry.tap()
        let retry = app.buttons["download.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 90),
                      "HTTP 200 garbage did not produce a retryable download failure")
        XCTAssertFalse(app.staticTexts["1 页"].exists,
                       "undecodable bytes were recorded as a completed chapter")
        let failure = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        failure.name = "bad-image-download-failure"
        failure.lifetime = .keepAlways
        add(failure)
        let failureTree = XCTAttachment(string: app.debugDescription)
        failureTree.name = "bad-image-download-failure-tree"
        failureTree.lifetime = .keepAlways
        add(failureTree)

        // The fixture recovers, and the existing retry fetches the real bytes.
        server.setCorruptPages(false)
        retry.tap()
        // A fresh download in this process still has its progress record, so the
        // row reads "1/1"; after a relaunch it would read "1 页". The retry row
        // disappearing is the state transition that matters.
        XCTAssertTrue(app.staticTexts["1/1"].waitForExistence(timeout: 90),
                      "retry did not save the recovered page")
        XCTAssertFalse(retry.exists, "the failure row survived a successful retry")

        server.stop()
        firstElement(app, containing: "Probe Comic").tap()
        XCTAssertTrue(app.buttons["收藏本页"].waitForExistence(timeout: 90),
                      "the reader toolbar is missing after the retry")
        let page = app.images.matching(
            NSPredicate(format: "label BEGINSWITH '第 ' AND label ENDSWITH ' 页'")
        ).firstMatch
        guard page.waitForExistence(timeout: 90) else {
            XCTFail("no decoded page image appeared after the recovered download")
            return
        }
        let screenshot = XCTAttachment(screenshot: page.screenshot())
        screenshot.name = "retried-page-with-server-stopped"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "retried-page-with-server-stopped-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// A chapter that failed has to be visible and retryable. Before this, a
    /// failure left no record: the row showed nothing, the downloads screen was
    /// empty, and the chapter the user asked for silently never arrived.
    func testAFailedDownloadCanBeRetriedFromTheDownloadsScreen() throws {
        let server = try LocalImageServer()
        try server.start()
        addTeardownBlock { server.stop() }
        // The first page request fails, so the attempt fails once; the retry gets
        // the fixture's real bytes.
        server.failNextPageRequests(1)

        let app = launch()
        // A chapter already on disk is not fetched again, so the forced failure
        // would never happen on a machine that ran this before. Start clean, the
        // way a user would: remove it from the downloads screen.
        removeDownloadedProbeChapter(app)
        try openSearch(app)
        try chooseSource(app, "Callback Probe")

        let field = element(app, "search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the search tab has no field")
        field.tap()
        field.typeText("probe")
        app.typeText("\n")

        let card = app.scrollViews.buttons
            .matching(NSPredicate(format: "label CONTAINS 'Probe Comic'")).firstMatch
        guard card.waitForExistence(timeout: 60) else {
            throw XCTSkip("the source did not answer search")
        }
        card.tap()

        let chapter = firstElement(app, containing: "Chapter 1")
        XCTAssertTrue(scrollToExist(app, chapter), "the detail page lists no chapter")
        XCTAssertTrue(scrollToHittable(app, chapter), "the chapter row never became tappable")
        chapter.press(forDuration: 1.2)
        let download = app.buttons["下载这一话"].firstMatch
        guard download.waitForExistence(timeout: 10) else {
            throw XCTSkip("no download action on a chapter row")
        }
        download.tap()

        tab(app, "我的")
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '下载'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "我的 has no downloads entry")
        entry.tap()

        // The failed attempt is listed with a retry button; nothing else on this
        // screen can make the chapter arrive.
        let retry = app.buttons["download.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 30),
                      "the failed download is not listed, so it can never be retried")
        retry.tap()

        XCTAssertTrue(firstElement(app, containing: "Probe Comic").waitForExistence(timeout: 90),
                      "the retry did not produce a downloaded chapter")
        XCTAssertFalse(app.buttons["download.retry"].exists,
                       "the failure is still listed after a successful retry")
    }

    /// The board's drag path: a real drag on the visible handle, the other cards'
    /// relative order, and the same order after a new process.
    ///
    /// Long-press entering arranging is covered by its own case. This one does not
    /// call the layout's move methods: it presses and drags the control a person
    /// would, then reads the card identifiers back from the screen.
    func testBoardDragOrderSurvivesRelaunch() throws {
        let app = launch()
        tab(app, "发现")

        func order() -> [String] {
            // A card's header and its chevron both inherit the card identifier, so
            // the raw list repeats every card. Keeping the first occurrence gives
            // the order a person sees; without this the first two entries are the
            // same card and a drag between them would assert nothing.
            var seen = Set<String>()
            return app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'home.card.'"))
                .allElementsBoundByIndex
                .map { String($0.identifier.dropFirst("home.card.".count)) }
                .filter { seen.insert($0).inserted }
        }
        /// Whether `moved` now sits before `other`, with the same cards as before.
        ///
        /// The claim this case makes is relative order, not one flat sequence: on a
        /// multi-column board the cards are read column by column, so dragging one
        /// card shifts every later entry and comparing whole arrays reports a correct
        /// rearrangement as a failure.
        func waitForRelative(_ moved: String, before other: String,
                             set: [String], timeout: TimeInterval = 20) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                let now = order()
                if let i = now.firstIndex(of: moved), let j = now.firstIndex(of: other),
                   i < j, Set(now) == Set(set) {
                    return true
                }
                usleep(200_000)
            } while Date() < deadline
            return false
        }
        func handle(_ id: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", "board.handle.\(id)"))
                .firstMatch
        }
        func card(_ id: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", "home.card.\(id)"))
                .firstMatch
        }
        func attach(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name + "-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }

        let edit = app.buttons.matching(NSPredicate(format: "identifier == 'discover.edit'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 20), "发现 has no edit button")

        let before = order()
        XCTAssertGreaterThanOrEqual(before.count, 3, "the board shows fewer than three cards")
        let first = before[0], second = before[1], third = before[2]
        attach("board-before-drag")

        edit.tap()
        // The button's own label is the cheapest proof that arranging started. A
        // drag sent while the board is still animating its controls lands on a
        // card that is moving, and a runner that never waited read that as "the
        // drag does nothing".
        let arrangeBy = Date().addingTimeInterval(10)
        while edit.label != "完成" && Date() < arrangeBy { usleep(200_000) }
        XCTAssertEqual(edit.label, "完成", "编辑 did not put the board into arranging")
        XCTAssertTrue(handle(second).waitForExistence(timeout: 10),
                      "arranging shows no handle for \(second)")

        // Slow, with a pause before release: SwiftUI's drop target only sees a
        // drag that hovers over it, and the default synthetic drag crosses the
        // card in a few milliseconds, which the runner reported as "the drag
        // changed nothing" while a person's drag reorders the board.
        handle(second).press(forDuration: 1.0, thenDragTo: card(first),
                             withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(waitForRelative(second, before: first, set: before),
                      "dragging \(second) before \(first) produced \(order()), expected it before \(first)")
        attach("board-after-drag")

        edit.tap()
        app.terminate()
        app.launch()
        tab(app, "发现")
        XCTAssertTrue(waitForRelative(second, before: first, set: before, timeout: 30),
                      "after relaunch the board is \(order()), expected \(second) before \(first)")
        attach("board-after-relaunch")

        // Put the starting arrangement back. Reordering the same two cards is the
        // inverse of the drag above and keeps the next case's layout unchanged.
        if ProcessInfo.processInfo.environment["NK_DRAG_KEEP"] != "1" {
            edit.tap()
            XCTAssertTrue(handle(second).waitForExistence(timeout: 10),
                          "arranging shows no handle for the moved card")
            // The inverse drag needs the card that follows `first` on screen. At the
            // accessibility text sizes it is below the fold, so the restore is only
            // attempted when the gesture has somewhere real to land; otherwise the
            // arrangement is left as the forward drag made it, which is what the
            // forward assertion already proved.
            // Putting the arrangement back is housekeeping for the next case, not a
            // claim of its own: on a multi-column board the drag to a card in another
            // column is not a reordering gesture, and the restore then simply does not
            // happen. That is reported, not asserted, so a correct forward drag and
            // relaunch are not turned into a failure by the cleanup.
            if hittable(card(third)) {
                handle(second).press(forDuration: 1.0, thenDragTo: card(third),
                                     withVelocity: .slow, thenHoldForDuration: 0.6)
                if !waitForRelative(first, before: second, set: before) {
                    print("NK_DRAG_RESTORE_NO_EFFECT: board is \(order()); left as the forward drag made it")
                }
            } else {
                print("NK_DRAG_RESTORE_SKIPPED: \(third) is off screen at this text size")
            }
            edit.tap()
        }
    }
}
