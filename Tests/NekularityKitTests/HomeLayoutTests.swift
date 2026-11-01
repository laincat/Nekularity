import Foundation
import Testing

@testable import NekularityKit

@Suite("HomeLayout")
@MainActor
struct HomeLayoutTests {
    private func store() -> HomeLayout {
        HomeLayout(defaults: UserDefaults(suiteName: "home-test-\(UUID().uuidString)")!)
    }

    @Test("everything ships enabled, in a fixed order")
    func defaults() {
        let layout = store()
        #expect(layout.blocks.count == HomeBlock.Template.allCases.count)
        #expect(layout.visible.count == layout.blocks.count)
        #expect(layout.blocks.first?.title == HomeBlock.Template.allCases.first?.title)
    }

    @Test("moving a block swaps it with its neighbour, and the order survives a relaunch")
    func moveAndPersist() {
        let defaults = UserDefaults(suiteName: "home-test-\(UUID().uuidString)")!
        let layout = HomeLayout(defaults: defaults)
        let first = layout.blocks[0]
        let second = layout.blocks[1]

        layout.move(first, by: 1)
        #expect(layout.blocks[0].id == second.id)
        #expect(layout.blocks[1].id == first.id)

        // Moving past the ends is a no-op rather than a crash.
        layout.move(layout.blocks[0], by: -1)
        #expect(layout.blocks[0].id == second.id)

        let again = HomeLayout(defaults: defaults)
        #expect(again.blocks[0].id == second.id)
        #expect(again.blocks[1].id == first.id)
    }

    @Test("a hidden block keeps its place instead of moving to the end")
    func hidingKeepsPosition() {
        let layout = store()
        let second = layout.blocks[1]
        layout.setEnabled(second, false)
        #expect(layout.blocks[1].id == second.id)
        #expect(!layout.visible.contains { $0.id == second.id })
        layout.setEnabled(second, true)
        #expect(layout.visible.contains { $0.id == second.id })
    }

    @Test("a source section is added once, and removed by identity")
    func sourceSections() {
        let layout = store()
        let ref = HomeBlock.SourceRef(key: "pixiv", sourceName: "Pixiv", index: 0, title: "日榜")
        layout.add(ref)
        layout.add(ref)
        let matches = layout.blocks.filter { $0.title == "日榜" }
        #expect(matches.count == 1, "the same section must not be added twice")
        #expect(matches.first?.subtitle == "Pixiv")

        if let block = matches.first { layout.remove(block) }
        #expect(!layout.blocks.contains { $0.title == "日榜" })
    }

    @Test("a template dropped by a later version is not resurrected, a new one appears")
    func loadRepairsTheList() throws {
        let defaults = UserDefaults(suiteName: "home-test-\(UUID().uuidString)")!
        // A saved order missing one template, which is what an older build writes.
        let partial = [HomeBlock(template: .favorites)]
        defaults.set(try JSONEncoder().encode(partial), forKey: "homeBlocksV2")

        let layout = HomeLayout(defaults: defaults)
        #expect(layout.blocks.contains { $0.title == HomeBlock.Template.favorites.title })
        #expect(layout.blocks.count == HomeBlock.Template.allCases.count,
                "a template missing from the saved order must be appended")
    }

    @Test("a template added in a later version appears, and a hidden one stays hidden")
    func migratesNewTemplates() {
        let defaults = UserDefaults(suiteName: "home-\(UUID().uuidString)")!
        // An arrangement saved before 继续观看、即将播出、本地漫画 existed.
        let old = [HomeBlock(template: .history), HomeBlock(template: .favorites, enabled: false)]
        defaults.set(try! JSONEncoder().encode(old), forKey: "homeBlocksV2")

        let layout = HomeLayout(defaults: defaults)
        #expect(layout.blocks.contains { $0.title == HomeBlock.Template.continueWatching.title })
        #expect(layout.blocks.contains { $0.title == HomeBlock.Template.upcoming.title })
        #expect(layout.blocks.contains { $0.title == HomeBlock.Template.localComics.title })
        // A block the user hid before the upgrade must not come back switched on.
        #expect(layout.blocks.first { $0.id == "template:favorites" }?.enabled == false)
        #expect(!layout.visible.contains { $0.id == "template:favorites" })
    }

    @Test("the new blocks claim the full width, since a strip needs it")
    func newBlocksAreWide() {
        for template in [HomeBlock.Template.continueWatching, .upcoming, .localComics] {
            #expect(HomeBlock(template: template).isWide)
        }
    }
}
