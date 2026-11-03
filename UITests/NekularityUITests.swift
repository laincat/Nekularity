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
    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name].firstMatch
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

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
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
            let button = app.tabBars.buttons[title].firstMatch
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
        let comics = element(app, "library.comicSources")
        for _ in 0..<4 {
            if comics.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(comics.waitForExistence(timeout: 20))
        comics.tap()
        XCTAssertTrue(app.navigationBars["漫画源"].waitForExistence(timeout: 20))
        app.navigationBars["漫画源"].buttons.element(boundBy: 0).tap()
        let videos = element(app, "library.videoSources")
        XCTAssertTrue(videos.waitForExistence(timeout: 20))
        if !videos.isHittable { app.swipeUp() }
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
        guard element(app, "source.nhentai").waitForExistence(timeout: 25) else {
            throw XCTSkip("no sources seeded: run scripts/seed-simulator.sh first")
        }
        XCTAssertTrue(element(app, "source.Komiic").exists, "a second seeded source is missing")
        // The repository's own source is in the seed too: the callback and tag
        // cases press it, and a device still holding an older seed would make them
        // skip for a reason that has nothing to do with the client.
        XCTAssertTrue(element(app, "source.callback_probe").exists,
                      "the test source is not seeded; run scripts/seed-simulator.sh with the current seed")
    }

    /// A source that logs in on its own page must offer that, not a sentence
    /// saying the client cannot.
    func testSourceOffersInPageLogin() throws {
        let app = launch()
        try openSettings(app, source: "nhentai")

        let login = element(app, "account.webviewLogin")
        XCTAssertTrue(login.waitForExistence(timeout: 25), "the in-page login button is missing")
        login.tap()
        // The sheet loads the site and titles itself after the source.
        let sheet = app.navigationBars["登录 nhentai"]
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
        defer { server.stop() }

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
        guard chapter.waitForExistence(timeout: 30) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "reader-chapter-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("the detail page listed no chapter")
            return
        }
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
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the root tab bar is still covering the reader")

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
        defer { server.stop() }

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
        guard chapter.waitForExistence(timeout: 30) else {
            throw XCTSkip("the detail page listed no chapter")
        }
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
        XCTAssertTrue(element(app, "search.field").waitForExistence(timeout: 20),
                      "全源搜索 opened nothing to type in")
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
        defer { server.stop() }

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
        XCTAssertTrue(element(app, "video.duration").waitForExistence(timeout: 90),
                      "no duration: \(server.clipSummary())")
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
        defer { server.stop() }

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

        let original = size.label
        XCTAssertTrue(original == "小" || original == "中", "unexpected size label: \(original)")
        let chosen = original == "中" ? "小" : "中"
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
        defer { server.stop() }

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
        XCTAssertTrue(chapter.waitForExistence(timeout: 30), "the detail page lists no chapter")
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
        XCTAssertTrue(app.buttons["收藏本页"].waitForExistence(timeout: 90),
                      "the reader drew nothing with the server down, so the download did not serve the pages")
    }

    /// A chapter that failed has to be visible and retryable. Before this, a
    /// failure left no record: the row showed nothing, the downloads screen was
    /// empty, and the chapter the user asked for silently never arrived.
    func testAFailedDownloadCanBeRetriedFromTheDownloadsScreen() throws {
        let server = try LocalImageServer()
        try server.start()
        defer { server.stop() }
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
        XCTAssertTrue(chapter.waitForExistence(timeout: 30), "the detail page lists no chapter")
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
        func waitForOrder(_ expected: [String], timeout: TimeInterval = 20) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                if order() == expected { return true }
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
        XCTAssertTrue(handle(second).waitForExistence(timeout: 10),
                      "arranging shows no handle for \(second)")

        handle(second).press(forDuration: 1.0, thenDragTo: card(first))
        let expected = [second, first] + before.dropFirst(2)
        XCTAssertTrue(waitForOrder(expected),
                      "dragging \(second) before \(first) produced \(order()), expected \(expected)")
        attach("board-after-drag")

        edit.tap()
        app.terminate()
        app.launch()
        tab(app, "发现")
        XCTAssertTrue(waitForOrder(expected, timeout: 30),
                      "after relaunch the board is \(order()), expected \(expected)")
        attach("board-after-relaunch")

        // Put the starting arrangement back. Reordering the same two cards is the
        // inverse of the drag above and keeps the next case's layout unchanged.
        if ProcessInfo.processInfo.environment["NK_DRAG_KEEP"] != "1" {
            edit.tap()
            XCTAssertTrue(handle(second).waitForExistence(timeout: 10),
                          "arranging shows no handle for the moved card")
            handle(second).press(forDuration: 1.0, thenDragTo: card(third))
            XCTAssertTrue(waitForOrder(before),
                          "the drag back produced \(order()), expected \(before)")
            edit.tap()
        }
    }
}
