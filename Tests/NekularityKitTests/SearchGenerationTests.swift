import Testing
@testable import NekularityKit

/// A search that started earlier must not write into the screen after a newer
/// search took over: its results belong to a keyword the user has replaced.
@Suite("search generation")
struct SearchGenerationTests {
    @Test func aNewSearchSupersedesTheOldOne() {
        let generation = SearchGeneration()
        let first = generation.begin()
        let second = generation.begin()
        #expect(generation.isCurrent(second))
        #expect(!generation.isCurrent(first))
    }

    @Test func anOldSearchCannotCommit() {
        let generation = SearchGeneration()
        let first = generation.begin()
        _ = generation.begin()
        var written = false
        generation.commit(first) { written = true }
        #expect(!written)
    }

    @Test func theCurrentSearchCanCommit() {
        let generation = SearchGeneration()
        let token = generation.begin()
        var written = false
        generation.commit(token) { written = true }
        #expect(written)
    }

    @Test func theFirstSearchIsCurrentUntilTheSecondBegins() {
        let generation = SearchGeneration()
        let first = generation.begin()
        #expect(generation.isCurrent(first))
        #expect(generation.currentToken == first)
    }
}
