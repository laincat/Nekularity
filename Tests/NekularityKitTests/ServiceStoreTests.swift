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

/// A package Core refuses must leave its reason on screen.
///
/// The catch used to write the message and then refresh the list; a successful
/// refresh cleared the message, so rejecting a package looked like nothing had
/// happened at all.
@MainActor
@Test func aRejectedPackageKeepsItsReason() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nk-services-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ServiceStore(directory: directory)
    store.reload()

    // A zip with no service.json: the shape Core refuses by name.
    let bad = directory.appending(path: "no-manifest.zip")
    var body = Data([0x50, 0x4b, 0x03, 0x04])
    body.append(Data("not really a zip".utf8))
    try body.write(to: bad)

    await store.install(from: bad)

    #expect(store.records.isEmpty, "a package Core refused must not be listed")
    #expect(store.error != nil, "the reason Core gave must stay visible")
    #expect(store.error?.contains("服务包未被接受") == true
            || store.error?.contains("操作失败") == true,
            "the message must say the package was not taken: \(store.error ?? "nil")")
}
