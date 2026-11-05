import Foundation
import Testing
@testable import NekularityKit

/// The shape Core writes for an installed service package. `service/store.go`
/// marshals `time.Time` as RFC3339 with nanoseconds and omits an empty digest
/// and an empty permission list, so the model has to accept both.
private let installed = """
[
  {
    "id": "weather",
    "name": "Weather",
    "version": "1.2.0",
    "origin": "https://example.test/weather.zip",
    "sha256": "9f2c",
    "installed": "2026-11-05T06:12:34.123456789Z",
    "dir": "/var/mobile/Library/Application Support/Nekularity/services/weather",
    "permissions": ["network", "storage"]
  },
  {
    "id": "plain",
    "name": "Plain",
    "version": "0.1.0",
    "origin": "https://example.test/plain.zip",
    "installed": "2026-11-05T06:13:00Z",
    "dir": "/var/mobile/Library/Application Support/Nekularity/services/plain"
  }
]
"""

@Test func aServiceListDecodesWhatCoreWrites() throws {
    let records = try JSONDecoder().decode([ServiceRecord].self, from: Data(installed.utf8))
    #expect(records.count == 2)
    #expect(records[0].id == "weather")
    #expect(records[0].sha256 == "9f2c")
    #expect(records[0].permissions == ["network", "storage"])
    // A package installed without a digest and without asking for anything is
    // still a package: the two optional fields must not make it undecodable.
    #expect(records[1].sha256 == nil)
    #expect(records[1].permissions == nil)
    #expect(records[1].installed == "2026-11-05T06:13:00Z")
}

/// An empty list is what Core answers when nothing is installed; a client that
/// treated it as an error would show a failure on a fresh install.
@Test func anEmptyServiceListIsNotAFailure() throws {
    let records = try JSONDecoder().decode([ServiceRecord].self, from: Data("[]".utf8))
    #expect(records.isEmpty)
}

/// The service id is what every other call takes, so the model uses it as the
/// identity rather than inventing its own.
@Test func theServiceIdentityIsTheCoreID() throws {
    let records = try JSONDecoder().decode([ServiceRecord].self, from: Data(installed.utf8))
    #expect(records.map(\.id) == ["weather", "plain"])
    #expect(records.map(\.name) == ["Weather", "Plain"])
}

/// A record Core cannot have written is reported as unreadable instead of being
/// silently dropped: a client showing an empty list for a malformed answer would
/// look like "nothing is installed".
@Test func aMalformedRecordIsReported() {
    let broken = #"{"id": "weather", "name": 3}"#
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(ServiceRecord.self, from: Data(broken.utf8))
    }
}

/// Error text names the thing that could not be read, in the language the rest
/// of the client speaks, and never leaks Core's English into the interface.
@Test func theUnreadableMessageNamesWhatFailed() {
    let error = CoreServiceError.unreadable("服务清单")
    #expect(error.errorDescription?.contains("服务清单") == true)
    #expect(error.errorDescription?.contains("unreadable") == false)
}
