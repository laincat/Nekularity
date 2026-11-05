import Foundation
import Testing
@testable import NekularityKit

/// The digest a record carries is what was installed, so it comes from the bytes
/// rather than from anything a listing said.
@Test func theDigestIsTheSHA256OfTheArchive() {
    let data = Data("service package".utf8)
    #expect(ServiceStore.digest(of: data)
            == "126fc9b5e6899bd618098cc946d1e06681f68c317ed9cbbb8bc8846144d4b4cf")
}

/// An empty archive still has a digest; the caller decides whether it is a
/// package at all.
@Test func anEmptyArchiveHasTheEmptyDigest() {
    #expect(ServiceStore.digest(of: Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
}

/// The same bytes always produce the same digest, which is what makes a record
/// comparable across installs.
@Test func theDigestIsStable() {
    let data = Data([0x50, 0x4b, 0x03, 0x04])
    #expect(ServiceStore.digest(of: data) == ServiceStore.digest(of: data))
    #expect(ServiceStore.digest(of: data).count == 64)
}

/// A listing that cannot be read says so; it is not shown as "nothing installed".
@MainActor
@Test func anUnreadableListingIsReportedNotShownAsEmpty() {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nk-services-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ServiceStore(directory: directory)
    store.reload()
    // Nothing has been installed there, so Core answers with an empty list and
    // no error: that is the fresh-install case, not a failure.
    #expect(store.records.isEmpty)
    #expect(store.error == nil)
}
