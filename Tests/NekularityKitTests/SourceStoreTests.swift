import Foundation
import Testing
@testable import NekularityKit

@Suite struct SourceStoreTests {
    func store() throws -> SourceStore {
        try SourceStore(root: FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)"))
    }

    @Test func dataRoundTripsExactly() throws {
        let s = try store()
        try s.saveData(key: "wnacg", dataKey: "big", json: #"{"n":12345678901234567890,"z":1,"a":2}"#)
        #expect(try s.loadData(key: "wnacg", dataKey: "big") == #"{"n":12345678901234567890,"z":1,"a":2}"#)
        // A fresh store reads the file.
        let again = try SourceStore(root: s.root)
        #expect(try again.loadData(key: "wnacg", dataKey: "big") == #"{"n":12345678901234567890,"z":1,"a":2}"#)
        try again.deleteData(key: "wnacg", dataKey: "big")
        #expect(try again.loadData(key: "wnacg", dataKey: "big") == nil)
    }

    @Test func loggedInMeansAnAccount() throws {
        let s = try store()
        #expect(!s.isLogged(key: "a"))
        try s.saveData(key: "a", dataKey: "account", json: #"["u","p"]"#)
        #expect(s.isLogged(key: "a"))
        try s.saveData(key: "a", dataKey: "account", json: "null")
        #expect(!s.isLogged(key: "a"))
    }

    @Test func keysCannotEscapeTheDirectory() throws {
        let s = try store()
        for bad in ["../x", "a/b", "", "a.b"] {
            #expect(throws: CoreError.self) { try s.saveData(key: bad, dataKey: "k", json: "1") }
        }
    }

    @Test func invalidJSONIsRejected() throws {
        let s = try store()
        #expect(throws: JSONParseError.self) { try s.saveData(key: "a", dataKey: "k", json: "{") }
    }
}
