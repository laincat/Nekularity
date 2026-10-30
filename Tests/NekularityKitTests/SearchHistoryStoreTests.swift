import Foundation
import Testing
@testable import NekularityKit

@MainActor
@Suite struct SearchHistoryStoreTests {
    func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "searches-\(UUID().uuidString)")
    }

    @Test func newestFirstAndCaseInsensitiveRepeats() {
        let store = SearchHistoryStore(directory: directory())
        for query in ["海贼王", "one piece", "  海贼王  "] {
            store.add(query)
        }
        #expect(store.queries == ["海贼王", "one piece"])

        store.add("ONE PIECE")
        #expect(store.queries == ["ONE PIECE", "海贼王"])
    }

    @Test func blankQueriesAreIgnored() {
        let store = SearchHistoryStore(directory: directory())
        store.add("   ")
        store.add("")
        #expect(store.queries.isEmpty)
    }

    @Test func listIsCapped() {
        let store = SearchHistoryStore(directory: directory())
        for i in 0..<(SearchHistoryStore.limit + 5) {
            store.add("q\(i)")
        }
        #expect(store.queries.count == SearchHistoryStore.limit)
        #expect(store.queries.first == "q\(SearchHistoryStore.limit + 4)")
    }

    @Test func mergeKeepsLocalQueriesFirst() {
        let store = SearchHistoryStore(directory: directory())
        store.add("本地")
        let added = store.merge(["旧的", "更旧的", "本地"])
        #expect(added == 2)
        #expect(store.queries == ["本地", "旧的", "更旧的"])
    }

    @Test func removeClearAndReload() {
        let dir = directory()
        let store = SearchHistoryStore(directory: dir)
        store.add("a")
        store.add("b")
        store.remove("A")
        #expect(store.queries == ["b"])

        let again = SearchHistoryStore(directory: dir)
        #expect(again.queries == ["b"])
        again.clear()
        #expect(SearchHistoryStore(directory: dir).queries.isEmpty)
    }

    @Test func brokenFileIsReported() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: dir.appending(path: "searches.json"))
        let store = SearchHistoryStore(directory: dir)
        #expect(store.queries.isEmpty)
        #expect(store.lastError != nil)
    }
}
