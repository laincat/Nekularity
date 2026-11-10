import Foundation
import Testing
@testable import NekularityKit

/// The inner gate that runs after ATS: default HTTPS, local addresses for any
/// partition, and one declared public host for comic and video sources only.
@Suite("Cleartext policy")
struct CleartextPolicyTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func httpsIsAlwaysAllowed() {
        for partition in ["comic:any", "video:any", "ai", "magpie", "service:x", "index", ""] {
            #expect(CleartextPolicy.allows(url("https://example.test/path"), partition: partition))
        }
    }

    @Test func aPublicCleartextAddressIsRefusedForTheAppsOwnRequests() {
        for partition in ["ai", "magpie", "service:fixture", "index", ""] {
            #expect(!CleartextPolicy.allows(url("http://example.test/path"), partition: partition),
                    "\(partition) must not use public http")
            #expect(!CleartextPolicy.allows(url("http://8.8.8.8/path"), partition: partition))
        }
    }

    @Test func aComicOrVideoSourceMayUseOnlyItsDeclaredHost() {
        for partition in ["comic:lanraragi", "video:kazumi"] {
            #expect(CleartextPolicy.allows(url("http://lrr.tvc-16.science/api/search"), partition: partition))
            #expect(!CleartextPolicy.allows(url("http://other.example.test/api"), partition: partition))
        }
        // The declared host stays a source exception; an AI provider cannot use it.
        #expect(!CleartextPolicy.allows(url("http://lrr.tvc-16.science/api"), partition: "ai"))
    }

    @Test func localAddressesAreAllowedEverywhere() {
        let local = [
            "http://localhost:8096/x",
            "http://127.0.0.1:18731/x",
            "http://127.10.20.30/x",
            "http://10.0.0.5/x",
            "http://172.16.0.1/x",
            "http://172.31.255.254/x",
            "http://192.168.1.9:8096/x",
            "http://169.254.10.1/x",
            "http://printer.local/x",
            "http://nuc.local:3000/x",
            "http://[::1]:8080/x",
            "http://[fe80::1]/x",
            "http://[fd12:3456::1]/x",
        ]
        for address in local {
            for partition in ["comic:x", "ai", "magpie", "service:x", "index"] {
                #expect(CleartextPolicy.allows(url(address), partition: partition),
                        "\(address) should be local for \(partition)")
            }
        }
    }

    @Test func aHostThatOnlyLooksLocalIsNotLocal() {
        // A suffix test that matched anywhere would let these through.
        for address in [
            "http://172.32.0.1/x",
            "http://11.0.0.1/x",
            "http://8.8.8.8/x",
            "http://notlocal.example/x",
            "http://local.example.test/x",
            "http://127.0.0.1.example.test/x",
        ] {
            #expect(!CleartextPolicy.allows(url(address), partition: "comic:x"),
                    "\(address) must not count as local")
        }
    }

    @Test func onlyHTTPAndHTTPSCount() {
        for address in ["file:///etc/passwd", "ftp://example.test/a", "http:///nohost"] {
            #expect(!CleartextPolicy.allows(url(address), partition: "comic:x"))
        }
    }
}
