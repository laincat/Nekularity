import Foundation
import Testing
@testable import NekularityKit

@Suite struct SourceSettingTests {
    /// Core answers a source's settings declaration as JSON; the client has to
    /// keep values that are not strings as they were written.
    @Test func decodesADeclaration() throws {
        let json = #"""
        [{"key":"region","title":"CDN线路","type":"select",
          "default":"1","options":[{"value":"1","text":"大陆线路"},{"value":"0","text":"海外线路"}]},
         {"key":"autoLogin","title":"自动登录","type":"switch","default":true},
         {"key":"limits","title":"上限","type":"input","default":20,"validator":"^[0-9]+$"},
         {"key":"refresh","title":"刷新","type":"callback"}]
        """#
        let list = try JSONDecoder().decode([SourceSetting].self, from: Data(json.utf8))
        #expect(list.count == 4)
        #expect(list[0].key == "region")
        #expect(list[0].kind == .choice)
        #expect(list[0].options?.count == 2)
        #expect(list[0].options?[1].text == "海外线路")
        #expect(list[0].default?.stringValue == "1")
        // A boolean and a number keep their shape.
        #expect(list[1].kind == .toggle)
        #expect(list[1].default?.stringValue == "true")
        #expect(list[2].kind == .text)
        #expect(list[2].default?.stringValue == "20")
        #expect(list[2].validator == "^[0-9]+$")
        #expect(list[3].kind == .action)
    }

    @Test func anEmptyAnswerIsAnEmptyList() throws {
        let list = try JSONDecoder().decode([SourceSetting].self, from: Data("[]".utf8))
        #expect(list.isEmpty)
    }
}

@MainActor
@Suite("SourceSettingsKit", .serialized)
struct SourceSettingsKitTests {
    private let script = """
    class SettingsProbe extends ComicSource {
        name = "Settings Probe"
        key = "settings_probe"
        version = "1.0.0"
        settings = {
            autoLogin: { title: "Auto", type: "switch", default: true },
            limit: { title: "Limit", type: "input", default: 20, validator: "^[0-9]+$" },
            ping: { title: "Ping", type: "callback", callback: () => "pong" },
        }
        search = { load: async (keyword, options, page) => ({ comics: [], maxPage: 1 }) }
    }
    """

    private func makeLibrary(_ root: URL) throws -> SourceLibrary {
        let jars = CookieJars(file: nil)
        let transport = URLSessionTransport(cookies: jars, defaultUserAgent: "nk-test/1")
        let host = CoreHost(store: try SourceStore(root: root), cookies: jars, transport: transport)
        let core = try CoreClient(config: CoreConfig(appVersion: "1.0", locale: "zh_CN",
                                                     defaultUserAgent: "nk-test/1"), host: host)
        return SourceLibrary(core: core, fetch: { _ in Data() })
    }

    @Test func loadMergesDefaultsAndInvalidSavePreservesOldValue() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let lib = try makeLibrary(root)
        _ = try await lib.install(script: script, origin: "test")

        let initial = try await lib.loadSettings(key: "settings_probe")
        #expect(initial.values["autoLogin"] == .bool(true))
        #expect(initial.values["limit"] == .number("20"))

        let limitSetting = try #require(initial.settings.first { $0.key == "limit" })
        #expect(try lib.saveSetting(key: "settings_probe", setting: limitSetting, value: .string("42")))
        #expect(!(try lib.saveSetting(key: "settings_probe", setting: limitSetting, value: .string("bad"))))

        let reloaded = try await lib.loadSettings(key: "settings_probe")
        #expect(reloaded.values["limit"] == .string("42"))

        let callbackAnswer = try await lib.runSettingCallback(key: "settings_probe", setting: "ping")
        #expect(callbackAnswer == "pong")
    }

    @Test func settingsStayIsolatedAcrossProfilesAndSurviveReopen() async throws {
        let rootA = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let rootB = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)

        let libA = try makeLibrary(rootA)
        _ = try await libA.install(script: script, origin: "test")
        let snapA = try await libA.loadSettings(key: "settings_probe")
        let toggle = try #require(snapA.settings.first { $0.key == "autoLogin" })
        #expect(try libA.saveSetting(key: "settings_probe", setting: toggle, value: .bool(false)))

        let libB = try makeLibrary(rootB)
        _ = try await libB.install(script: script, origin: "test")
        let snapB = try await libB.loadSettings(key: "settings_probe")
        #expect(snapB.values["autoLogin"] == .bool(true))

        let reopenedA = try makeLibrary(rootA)
        await reopenedA.restore()
        let snapReopenedA = try await reopenedA.loadSettings(key: "settings_probe")
        #expect(snapReopenedA.values["autoLogin"] == .bool(false))
    }
}
