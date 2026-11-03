import Foundation
import Testing
@testable import NekularityKit

@Suite struct MagpieSignInBindingTests {
    @Test func immediateAuthReachesExistingCore() async throws {
        try await verifyBinding(polled: false)
    }

    @Test func polledAuthReachesExistingCore() async throws {
        try await verifyBinding(polled: true)
    }

    private func verifyBinding(polled: Bool) async throws {
        try await Task.detached {
            let core = try CoreMagpie()
            let store = MemoryMagpieAuthStore()
            let runner = MagpieRunner(core: core, store: store)
            defer { runner.close() }
            let provider = "binding-fixture"
            let result = #"{type: 'success', key: 'fixture-key', metadata: {baseURL: 'http://127.0.0.1:52970'}}"#
            let authorize = polled ? "{callback: async () => (\(result))}" : result
            let source = """
            export async function Plugin() {
              return {auth: {provider: 'binding-fixture', methods: [{kind: 'key', label: 'fixture',
                authorize: async () => (\(authorize))}]}};
            }
            export async function readBoundAuth() {
              return await globalThis.__magpieClient.auth.get({path: {id: 'binding-fixture'}});
            }
            """
            try runner.install(provider: provider, files: [
                "package.json": Data(#"{"name":"binding-fixture","version":"1.0.0","main":"./index.mjs"}"#.utf8),
                "index.mjs": Data(source.utf8)
            ])
            _ = try runner.auth(provider: provider)
            let session = runner.makeSignIn(provider: provider, pollInterval: .milliseconds(1))
            _ = try session.start(methodIndex: 0)
            let outcome = await session.waitForResult()
            guard case .success = outcome else {
                Issue.record("fixture sign-in failed: \(outcome)")
                return
            }
            let savedJSON = try store.loadAuthJSON(provider: provider)
            let saved = try #require(savedJSON)
            let bound = try core.call("readBoundAuth", argJSON: "{}")
            #expect(bound != "null", "successful sign-in must bind the current Core, not only persist it")
            let savedData = Data(saved.utf8)
            let boundData = Data(bound.utf8)
            let savedObject = try JSONSerialization.jsonObject(with: savedData, options: .fragmentsAllowed) as? NSDictionary
            let boundObject = try JSONSerialization.jsonObject(with: boundData, options: .fragmentsAllowed) as? NSDictionary
            #expect(boundObject == savedObject, "same runtime must see the stored key and metadata without a restart")
        }.value
    }
}
