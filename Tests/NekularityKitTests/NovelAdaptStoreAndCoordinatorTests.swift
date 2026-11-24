import Foundation
import Testing
@testable import NekularityKit

private final class StubAdaptClient: NovelAdaptClient, @unchecked Sendable {
    private let lock = NSLock()
    private var adaptHandlers: [@Sendable (AdaptChapterRequest) throws -> AdaptChapterResponse] = []
    private var panelHandlers: [@Sendable (RenderPanelRequest) throws -> RenderPanelResponse] = []
    private var storyboardHandlers: [@Sendable (RenderStoryboardRequest) throws -> RenderStoryboardResponse] = []
    private(set) var recordedAdaptRequests: [AdaptChapterRequest] = []
    private(set) var recordedPanelRequests: [RenderPanelRequest] = []
    private(set) var recordedStoryboardRequests: [RenderStoryboardRequest] = []

    func enqueueAdapt(_ handler: @escaping @Sendable (AdaptChapterRequest) throws -> AdaptChapterResponse) {
        lock.lock(); defer { lock.unlock() }
        adaptHandlers.append(handler)
    }

    func enqueuePanel(_ handler: @escaping @Sendable (RenderPanelRequest) throws -> RenderPanelResponse) {
        lock.lock(); defer { lock.unlock() }
        panelHandlers.append(handler)
    }

    func enqueueStoryboard(_ handler: @escaping @Sendable (RenderStoryboardRequest) throws -> RenderStoryboardResponse) {
        lock.lock(); defer { lock.unlock() }
        storyboardHandlers.append(handler)
    }

    func adaptChapter(_ request: AdaptChapterRequest) async throws -> AdaptChapterResponse {
        let handler: (@Sendable (AdaptChapterRequest) throws -> AdaptChapterResponse)? = lock.withLock {
            recordedAdaptRequests.append(request)
            return adaptHandlers.isEmpty ? nil : adaptHandlers.removeFirst()
        }
        guard let handler else { throw CoreError("unexpected adaptChapter call") }
        return try handler(request)
    }

    func renderPanel(_ request: RenderPanelRequest) async throws -> RenderPanelResponse {
        let handler: (@Sendable (RenderPanelRequest) throws -> RenderPanelResponse)? = lock.withLock {
            recordedPanelRequests.append(request)
            return panelHandlers.isEmpty ? nil : panelHandlers.removeFirst()
        }
        guard let handler else { throw CoreError("unexpected renderPanel call") }
        return try handler(request)
    }

    func renderStoryboard(_ request: RenderStoryboardRequest) async throws -> RenderStoryboardResponse {
        let handler: (@Sendable (RenderStoryboardRequest) throws -> RenderStoryboardResponse)? = lock.withLock {
            recordedStoryboardRequests.append(request)
            return storyboardHandlers.isEmpty ? nil : storyboardHandlers.removeFirst()
        }
        guard let handler else { throw CoreError("unexpected renderStoryboard call") }
        return try handler(request)
    }
}

/// Covers `NovelAdaptStore` persistence, corrupt manifest rescue, path-traversal
/// defense, zero API-key leakage, and `NovelAdaptCoordinator` checkpoint resume,
/// reference injection, panel caching, and single-panel `ForceRerender`.
@MainActor
@Suite("Novel adapt store & coordinator")
struct NovelAdaptStoreAndCoordinatorTests {
    private static let pngBytesA = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
    ])

    // Minimal valid RIFF/WEBP header bytes for MIME switch cleanup test.
    private static let webpBytesB = Data([
        0x52, 0x49, 0x46, 0x46, 0x1A, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20,
        0x0E, 0x00, 0x00, 0x00, 0x30, 0x01, 0x00, 0x9D,
        0x01, 0x2A, 0x01, 0x00, 0x01, 0x00,
    ])

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nk-adapt-store-\(UUID().uuidString)")
    }

    @Test func checkpointResumePersistsAcrossReloadAndClearsOnCompletion() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = NovelAdaptStore(directory: dir)
        let client = StubAdaptClient()
        let coordinator = NovelAdaptCoordinator(projectID: "proj-resume", client: client, store: store)
        coordinator.ensureProject(
            title: "Night Bell",
            novelSourceKey: "novel_src",
            novelID: "n1",
            budget: AdaptBudget(maxCalls: 1)
        )

        let chapter = NovelChapter(id: "ch1", title: "Chapter 1")
        let content = NovelChapterContent(html: "<p>Part 1</p><p>Part 2</p>")
        let textConfig = AdaptTextConfig(
            protocol: .chat,
            baseURL: "https://ai.example.test/v1",
            apiKey: "sk-TEXT-SECRET-NEVER-PERSIST-001",
            model: "gpt-test"
        )

        // Pass 1: hits budget cap after chunk 1 -> returns partial checkpoint.
        client.enqueueAdapt { req in
            #expect(req.options?.checkpoint == nil)
            var proj = req.project
            let char = AdaptCharacter(id: "c1", name: "Wen", appearance: "dark hair", outfit: "coat", firstChapterID: "ch1")
            proj.characters.characters = [char]
            proj.usage = AdaptUsage(calls: 1, inputTokens: 40, outputTokens: 20, totalTokens: 60)
            let partialSB = AdaptStoryboard(
                chapterID: "ch1",
                chapterTitle: "Chapter 1",
                scenes: [
                    AdaptScene(id: "s1", setting: "Street", panels: [
                        AdaptPanel(id: "p1", shot: "wide", action: "Steps out", prompt: "rainy street")
                    ])
                ]
            )
            let cp = AdaptCheckpoint(
                chapterID: "ch1",
                chapterTitle: "Chapter 1",
                totalChunks: 2,
                completedChunks: 1,
                maxChunkRunes: 18,
                storyboard: partialSB,
                characters: proj.characters,
                addedCharacters: [char],
                usage: proj.usage,
                sceneSeq: 1,
                panelSeq: 1
            )
            return AdaptChapterResponse(
                completed: false,
                project: proj,
                result: AdaptResult(
                    storyboard: partialSB,
                    addedCharacters: [char],
                    chunks: 2,
                    completedChunks: 1,
                    usage: proj.usage,
                    checkpoint: cp
                ),
                error: "adapt: budget exceeded: calls 1 reached limit 1",
                errorCode: "budget_exceeded"
            )
        }

        let pass1 = try await coordinator.adaptChapter(chapter, content: content, textConfig: textConfig, maxChunkRunes: 18)
        #expect(!pass1.completed)
        #expect(coordinator.phase == .paused(
            chapterID: "ch1",
            errorCode: .budgetExceeded,
            message: AdaptErrorCode.budgetExceeded.readableMessage
        ))
        #expect(coordinator.checkpoint(for: "ch1")?.completedChunks == 1)
        #expect(coordinator.characters.map(\.name) == ["Wen"])

        // Reload store from disk to prove checkpoint & character sheet survived restart.
        let reloadedStore = NovelAdaptStore(directory: dir)
        reloadedStore.updateBudget(projectID: "proj-resume", budget: AdaptBudget(maxCalls: 4))
        let reloadedCoordinator = NovelAdaptCoordinator(projectID: "proj-resume", client: client, store: reloadedStore)
        #expect(reloadedCoordinator.checkpoint(for: "ch1")?.completedChunks == 1)
        #expect(reloadedCoordinator.characters.map(\.name) == ["Wen"])

        // Pass 2: resumes automatically with saved checkpoint and finishes chapter.
        client.enqueueAdapt { req in
            #expect(req.options?.checkpoint?.completedChunks == 1)
            #expect(req.project.budget.maxCalls == 4)
            var proj = req.project
            let fullSB = AdaptStoryboard(
                chapterID: "ch1",
                chapterTitle: "Chapter 1",
                scenes: [
                    AdaptScene(id: "s1", setting: "Street", panels: [
                        AdaptPanel(id: "p1", shot: "wide", action: "Steps out", prompt: "rainy street")
                    ]),
                    AdaptScene(id: "s2", setting: "Hallway", panels: [
                        AdaptPanel(id: "p2", shot: "close", action: "Holds key", prompt: "brass key")
                    ]),
                ]
            )
            proj.storyboards["ch1"] = fullSB
            proj.usage = AdaptUsage(calls: 2, inputTokens: 80, outputTokens: 40, totalTokens: 120)
            return AdaptChapterResponse(
                completed: true,
                project: proj,
                result: AdaptResult(storyboard: fullSB, chunks: 2, completedChunks: 2, usage: proj.usage, checkpoint: nil)
            )
        }

        let pass2 = try await reloadedCoordinator.adaptChapter(chapter, content: content, textConfig: textConfig)
        #expect(pass2.completed)
        #expect(reloadedCoordinator.phase == .completed(chapterID: "ch1"))
        #expect(reloadedCoordinator.checkpoint(for: "ch1") == nil)
        #expect(reloadedCoordinator.storyboard(for: "ch1")?.panelCount == 2)

        // Verify persisted files contain ZERO trace of API keys.
        try assertNoSecretInDirectory(dir, secrets: ["sk-TEXT-SECRET-NEVER-PERSIST-001"])
    }

    @Test func localReferencesPanelCacheForceRerenderAndZeroKeyLeakage() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = NovelAdaptStore(directory: dir)
        let client = StubAdaptClient()
        let coordinator = NovelAdaptCoordinator(projectID: "proj-render", client: client, store: store)
        var project = coordinator.ensureProject(title: "Static Comic")
        project.storyboards["ch1"] = AdaptStoryboard(
            chapterID: "ch1",
            scenes: [
                AdaptScene(id: "s1", setting: "Tower", panels: [
                    AdaptPanel(id: "p1", shot: "wide", action: "Looks up", characters: ["Wen"], prompt: "tower"),
                    AdaptPanel(id: "p2", shot: "close", action: "Smiles", characters: ["Wen"], prompt: "portrait"),
                ])
            ]
        )
        store.upsertProject(project)

        // Store local style and character references.
        let styleRef = try store.saveReferenceImage(
            projectID: "proj-render",
            kind: .style,
            label: "Watercolor",
            mimeType: "image/png",
            data: Self.pngBytesA,
            id: "style-ref-1"
        )
        let charRef = try store.saveReferenceImage(
            projectID: "proj-render",
            kind: .character,
            characterKey: "Wen",
            label: "Wen Portrait",
            mimeType: "image/png",
            data: Self.pngBytesA,
            id: "char-ref-1"
        )
        #expect(store.loadReferenceImageData(projectID: "proj-render", referenceID: styleRef.id) == Self.pngBytesA)
        #expect(store.loadReferenceImageData(projectID: "proj-render", referenceID: charRef.id) == Self.pngBytesA)

        let imageConfig = AdaptImageConfig(
            provider: .gemini,
            baseURL: "https://gemini.example.test/v1beta",
            apiKey: "gem-IMAGE-SECRET-NEVER-PERSIST-002",
            model: "gemini-2.5-flash-image"
        )

        // Storyboard render: p1 rendered, p2 blocked -> caches p1 and pauses with content_blocked.
        client.enqueueStoryboard { req in
            #expect(req.options?.styleReferences.map(\.id) == ["style-ref-1"])
            #expect(req.options?.characterReferences["Wen"]?.map(\.id) == ["char-ref-1"])
            var updated = req.project
            updated.storyboards["ch1"]?.scenes[0].panels[0].imageStatus = .done
            updated.storyboards["ch1"]?.scenes[0].panels[0].imageRefID = "ch1/s1/p1"
            updated.storyboards["ch1"]?.scenes[0].panels[1].imageStatus = .failed
            updated.storyboards["ch1"]?.scenes[0].panels[1].imageError = "adapt: image generation blocked by content policy"
            return RenderStoryboardResponse(
                completed: false,
                project: updated,
                result: RenderSummary(
                    chapterID: "ch1",
                    rendered: 1,
                    skipped: 0,
                    failed: 1,
                    blocked: 1,
                    usage: AdaptUsage(imageCalls: 1),
                    failures: [
                        AdaptPanelFailure(
                            sceneID: "s1",
                            panelID: "p2",
                            error: "adapt: image generation blocked by content policy",
                            errorCode: "content_blocked"
                        )
                    ]
                ),
                images: [
                    RenderedPanelImage(
                        sceneID: "s1",
                        panelID: "p1",
                        refID: "ch1/s1/p1",
                        mimeType: "image/png",
                        dataBase64: Self.pngBytesA.base64EncodedString()
                    )
                ],
                error: "adapt: image generation blocked by content policy",
                errorCode: "content_blocked"
            )
        }

        let sbResp = try await coordinator.renderStoryboard(
            chapterID: "ch1",
            imageConfig: imageConfig,
            options: AdaptRenderOptions(continueOnError: true)
        )
        #expect(!sbResp.completed)
        #expect(coordinator.phase == .paused(
            chapterID: "ch1",
            errorCode: .contentBlocked,
            message: AdaptErrorCode.contentBlocked.readableMessage
        ))
        #expect(coordinator.panelImageData(chapterID: "ch1", sceneID: "s1", panelID: "p1") == Self.pngBytesA)
        let oldPNGURL = try #require(coordinator.panelImageURL(chapterID: "ch1", sceneID: "s1", panelID: "p1"))
        #expect(oldPNGURL.pathExtension == "png")

        // Single-panel ForceRerender returning WebP replaces cached bytes and deletes stale PNG file.
        client.enqueuePanel { req in
            #expect(req.options?.forceRerender == true)
            #expect(req.options?.styleReferences.map(\.id) == ["style-ref-1"])
            return RenderPanelResponse(
                project: req.project,
                sceneID: "s1",
                panelID: "p1",
                refID: "ch1/s1/p1",
                skipped: false,
                mimeType: "image/webp",
                dataBase64: Self.webpBytesB.base64EncodedString(),
                revisedPrompt: "sharper moonlight",
                usage: AdaptUsage(imageCalls: 1)
            )
        }

        let rerender = try await coordinator.rerenderPanel(
            chapterID: "ch1",
            sceneID: "s1",
            panelID: "p1",
            imageConfig: imageConfig
        )
        #expect(!rerender.skipped)
        #expect(coordinator.phase == .completed(chapterID: "ch1"))
        #expect(coordinator.panelImageData(chapterID: "ch1", sceneID: "s1", panelID: "p1") == Self.webpBytesB)
        let newWebPURL = try #require(coordinator.panelImageURL(chapterID: "ch1", sceneID: "s1", panelID: "p1"))
        #expect(newWebPURL.pathExtension == "webp")
        #expect(!FileManager.default.fileExists(atPath: oldPNGURL.path))

        // Reload store from disk and confirm panel cache & references survive intact.
        let reopened = NovelAdaptStore(directory: dir)
        #expect(reopened.loadPanelImageData(projectID: "proj-render", chapterID: "ch1", sceneID: "s1", panelID: "p1") == Self.webpBytesB)
        #expect(reopened.panelImageEntry(projectID: "proj-render", chapterID: "ch1", sceneID: "s1", panelID: "p1")?.revisedPrompt == "sharper moonlight")
        #expect(reopened.referenceImages(projectID: "proj-render").count == 2)

        try assertNoSecretInDirectory(dir, secrets: ["gem-IMAGE-SECRET-NEVER-PERSIST-002"])
    }

    @Test func pathTraversalDefenseAndCorruptManifestRescue() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1. Malicious filename and IDs must stay strictly inside `dir`.
        let store = NovelAdaptStore(directory: dir, filename: "../../escape.json")
        store.upsertProject(AdaptProject(id: "../../bad/proj", title: "Evil IDs"))
        let savedPanel = try store.savePanelImage(
            projectID: "../../bad/proj",
            chapterID: "../ch1",
            sceneID: "s1/../../x",
            panelID: "..\\p1",
            refID: "../ref",
            mimeType: "image/png",
            data: Self.pngBytesA
        )
        let resolvedURL = try #require(store.panelImageURL(
            projectID: "../../bad/proj",
            chapterID: "../ch1",
            sceneID: "s1/../../x",
            panelID: "..\\p1"
        ))
        let rootPrefix = dir.standardizedFileURL.path + "/"
        #expect(resolvedURL.standardizedFileURL.path.hasPrefix(rootPrefix))
        #expect(!savedPanel.relativePath.contains(".."))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape.json").path))

        // 2. Tampered manifest pointing outside root must be rejected on read.
        let outsideFile = dir.deletingLastPathComponent().appendingPathComponent("nk-outside-\(UUID().uuidString).txt")
        try Data("TOP-SECRET".utf8).write(to: outsideFile, options: .atomic)
        defer { try? FileManager.default.removeItem(at: outsideFile) }

        let tamperedDir = tempDir()
        defer { try? FileManager.default.removeItem(at: tamperedDir) }
        try FileManager.default.createDirectory(at: tamperedDir, withIntermediateDirectories: true)
        let tamperedManifest = """
        {
          "version": 1,
          "workspaces": {
            "p1": {
              "project": {"id": "p1", "title": "Tampered", "characters": {"characters": []}, "usage": {"calls": 0, "inputTokens": 0, "outputTokens": 0, "totalTokens": 0}},
              "checkpoints": {},
              "references": [
                {"id": "ref1", "kind": "style", "mimeType": "image/png", "relativePath": "../\(outsideFile.lastPathComponent)", "byteCount": 10, "sha256": "abc", "addedAt": 1}
              ],
              "panelImages": {
                "ch1|s1|p1": {"chapterID": "ch1", "sceneID": "s1", "panelID": "p1", "refID": "ch1/s1/p1", "mimeType": "image/png", "relativePath": "../../\(outsideFile.lastPathComponent)", "byteCount": 10, "sha256": "abc", "renderedAt": 1}
              },
              "createdAt": 1,
              "updatedAt": 1
            }
          }
        }
        """
        try Data(tamperedManifest.utf8).write(
            to: tamperedDir.appendingPathComponent(NovelAdaptStore.defaultFilename),
            options: .atomic
        )
        let tamperedStore = NovelAdaptStore(directory: tamperedDir)
        #expect(tamperedStore.loadPanelImageData(projectID: "p1", chapterID: "ch1", sceneID: "s1", panelID: "p1") == nil)
        #expect(tamperedStore.panelImageURL(projectID: "p1", chapterID: "ch1", sceneID: "s1", panelID: "p1") == nil)
        #expect(tamperedStore.loadReferenceImageData(projectID: "p1", referenceID: "ref1") == nil)
        let refOpts = tamperedStore.buildReferenceOptions(projectID: "p1")
        #expect(refOpts.style.isEmpty)
        #expect(refOpts.characters.isEmpty)

        // 3. Corrupt manifest is copied aside via StoreRescue rather than silently lost.
        let corruptDir = tempDir()
        defer { try? FileManager.default.removeItem(at: corruptDir) }
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        let manifestURL = corruptDir.appendingPathComponent(NovelAdaptStore.defaultFilename)
        let garbage = Data("{broken json".utf8)
        try garbage.write(to: manifestURL, options: .atomic)

        let rescuedStore = NovelAdaptStore(directory: corruptDir)
        #expect(rescuedStore.workspaces.isEmpty)
        #expect(rescuedStore.lastError != nil)
        let copies = StoreRescue.copies(of: manifestURL)
        #expect(copies.count == 1)
        #expect((try? Data(contentsOf: copies[0])) == garbage)

        // Saving new work afterwards still keeps the rescued copy intact.
        rescuedStore.upsertProject(AdaptProject(id: "fresh", title: "Fresh"))
        #expect(StoreRescue.copies(of: manifestURL).count == 1)
        #expect(NovelAdaptStore(directory: corruptDir).workspace(id: "fresh")?.project.title == "Fresh")
    }

    private func assertNoSecretInDirectory(_ root: URL, secrets: [String]) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return
        }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: fileURL)
            let text = String(decoding: data, as: UTF8.self)
            for secret in secrets {
                #expect(!text.contains(secret), "secret leaked into persisted file \(fileURL.lastPathComponent)")
            }
        }
    }
}
