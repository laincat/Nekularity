import Foundation
import Testing
@testable import NekularityKit

/// Covers Wave 4B adaptation domain/wire JSON codecs (both `JSONEncoder`/`JSONDecoder`
/// and Core's `OrderedJSONDecoder`) as well as readable error mappings.
@Suite("Adapt models & error mapping")
struct AdaptModelsTests {
    private static let samplePNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4z8AAAAMBAQAY3Y2wAAAAAElFTkSuQmCC"

    @Test func adaptChapterRequestAndPartialResponseRoundTrip() throws {
        let project = AdaptProject(
            id: "proj-1",
            novelSourceKey: "src_novel",
            novelID: "n1",
            title: "Starlit Tower",
            styleRef: AdaptStyleRef(
                comicSourceKey: "src_comic",
                comicID: "c1",
                comicTitle: "Ink Style",
                referencePageIDs: ["p1", "p2"],
                styleNotes: "clean ink lines"
            ),
            characters: AdaptCharacterSheet(characters: [
                AdaptCharacter(
                    id: "char_1",
                    name: "Lin",
                    aliases: ["Little Lin"],
                    appearance: "short black hair",
                    outfit: "dark coat",
                    traits: ["calm"],
                    firstChapterID: "ch1",
                    notes: "carries a lantern"
                )
            ]),
            budget: AdaptBudget(maxCalls: 3, maxImageCalls: 6, maxTotalTokens: 10_000),
            usage: AdaptUsage(calls: 1, imageCalls: 0, inputTokens: 120, outputTokens: 80, totalTokens: 200)
        )
        let checkpoint = AdaptCheckpoint(
            chapterID: "ch1",
            chapterTitle: "Chapter 1",
            totalChunks: 2,
            completedChunks: 1,
            maxChunkRunes: 1800,
            storyboard: AdaptStoryboard(
                chapterID: "ch1",
                chapterTitle: "Chapter 1",
                scenes: [
                    AdaptScene(
                        id: "s1",
                        setting: "Rainy alley",
                        mood: "tense",
                        panels: [
                            AdaptPanel(
                                id: "p1",
                                shot: "wide",
                                action: "Lin steps out",
                                characters: ["Lin"],
                                dialogues: [AdaptDialogue(speaker: "Lin", text: "Wait.", kind: "speech")],
                                prompt: "wide shot rainy alley dark coat",
                                imageStatus: .pending
                            )
                        ]
                    )
                ]
            ),
            characters: project.characters,
            addedCharacters: project.characters.characters,
            usage: project.usage,
            sceneSeq: 1,
            panelSeq: 1
        )
        let request = AdaptChapterRequest(
            project: project,
            chapter: NovelChapter(id: "ch1", title: "Chapter 1", time: "2026-11-24"),
            content: NovelChapterContent(html: "<p>Rain falls.</p>"),
            text: AdaptTextConfig(
                protocol: .responses,
                baseURL: "https://ai.example.test/v1",
                apiKey: "secret-key",
                model: "gpt-test",
                maxTokens: 2048,
                temperature: 0.2,
                jsonMode: true,
                reasoningEffort: "medium"
            ),
            options: AdaptOptions(maxChunkRunes: 1800, checkpoint: checkpoint)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let encoded = try encoder.encode(request)
        let encodedText = String(decoding: encoded, as: UTF8.self)
        #expect(encodedText.contains(#""novelId":"n1""#))
        #expect(encodedText.contains(#""baseUrl":"https://ai.example.test/v1""#))
        #expect(encodedText.contains(#""chapterId":"ch1""#))
        #expect(encodedText.contains(#""firstChapterId":"ch1""#))
        #expect(encodedText.contains(#""referencePageIds":["p1","p2"]"#))

        let decodedReq = try OrderedJSONDecoder.decode(AdaptChapterRequest.self, from: encodedText)
        #expect(decodedReq == request)

        // Core partial budget-exceeded JSON response with omitted optional fields.
        let coreResponseJSON = """
        {
          "completed": false,
          "project": {
            "id": "proj-1",
            "title": "Starlit Tower",
            "characters": {"characters": [{"id": "char_1", "name": "Lin"}]},
            "storyboards": {"ch0": null},
            "budget": {"maxCalls": 1},
            "usage": {"calls": 1, "inputTokens": 50, "outputTokens": 30, "totalTokens": 80}
          },
          "result": {
            "storyboard": {
              "chapterId": "ch1",
              "scenes": [{"id": "s1", "setting": "Alley", "panels": [{"id": "p1", "shot": "wide", "action": "Walks", "prompt": "alley", "imageStatus": "pending"}]}]
            },
            "chunks": 2,
            "completedChunks": 1,
            "usage": {"calls": 1, "inputTokens": 50, "outputTokens": 30, "totalTokens": 80},
            "checkpoint": {
              "chapterId": "ch1",
              "totalChunks": 2,
              "completedChunks": 1,
              "maxChunkRunes": 18,
              "characters": {"characters": [{"id": "char_1", "name": "Lin"}]},
              "usage": {"calls": 1, "inputTokens": 50, "outputTokens": 30, "totalTokens": 80},
              "sceneSeq": 1,
              "panelSeq": 1
            }
          },
          "error": "adapt: budget exceeded: calls 1 reached limit 1",
          "errorCode": "budget_exceeded"
        }
        """

        let response = try OrderedJSONDecoder.decode(AdaptChapterResponse.self, from: coreResponseJSON)
        #expect(!response.completed)
        #expect(response.parsedErrorCode == .budgetExceeded)
        #expect(response.project.storyboards.isEmpty)
        #expect(response.project.budget.maxCalls == 1)
        #expect(response.project.budget.maxImageCalls == 0)
        #expect(response.result?.chunks == 2)
        #expect(response.result?.completedChunks == 1)
        #expect(response.result?.checkpoint?.maxChunkRunes == 18)
        #expect(response.result?.checkpoint?.sceneSeq == 1)
        #expect(response.result?.checkpoint?.panelSeq == 1)
    }

    @Test func renderPanelAndStoryboardWireCodecs() throws {
        let pngData = try #require(Data(base64Encoded: Self.samplePNGBase64))
        let styleRef = AdaptImageRef(id: "style-1", kind: .style, label: "Ink", mimeType: "image/png", data: pngData)
        let charRef = AdaptImageRef(id: "char-1", kind: .character, label: "Lin", mimeType: "image/png", data: pngData)

        let panelReq = RenderPanelRequest(
            project: AdaptProject(id: "proj-2", title: "Demo"),
            chapterID: "ch1",
            sceneID: "s1",
            panelID: "p1",
            image: AdaptImageConfig(
                provider: .gemini,
                baseURL: "https://gemini.example.test/v1beta",
                apiKey: "gem-key",
                model: "gemini-2.5-flash-image",
                responseModalities: ["IMAGE"]
            ),
            options: AdaptRenderOptions(
                aspectRatio: "3:4",
                maxRetries: 2,
                forceRerender: true,
                styleReferences: [styleRef],
                characterReferences: ["Lin": [charRef]],
                feedbackCharacterRefs: true
            )
        )
        let panelReqJSON = String(decoding: try JSONEncoder().encode(panelReq), as: UTF8.self)
        #expect(panelReqJSON.contains(#""chapterId":"ch1""#))
        #expect(panelReqJSON.contains(#""sceneId":"s1""#))
        #expect(panelReqJSON.contains(#""panelId":"p1""#))
        #expect(panelReqJSON.contains(#""forceRerender":true"#))
        #expect(try OrderedJSONDecoder.decode(RenderPanelRequest.self, from: panelReqJSON) == panelReq)

        // Legacy `data` field on AdaptImageRef decodes into `dataBase64`.
        let legacyRefJSON = #"{"id":"r1","kind":"style","mimeType":"image/png","data":"\#(Self.samplePNGBase64)"}"#
        let legacyRef = try OrderedJSONDecoder.decode(AdaptImageRef.self, from: legacyRefJSON)
        #expect(legacyRef.decodedData == pngData)

        let panelRespJSON = """
        {
          "project": {"id": "proj-2", "title": "Demo", "characters": {"characters": []}, "usage": {"calls": 0, "imageCalls": 1, "inputTokens": 0, "outputTokens": 0, "totalTokens": 0}},
          "sceneId": "s1",
          "panelId": "p1",
          "refId": "ch1/s1/p1",
          "mimeType": "image/png",
          "dataBase64": "\(Self.samplePNGBase64)",
          "revisedPrompt": "dramatic ink lighting",
          "usage": {"calls": 0, "imageCalls": 1, "inputTokens": 10, "outputTokens": 20, "totalTokens": 30}
        }
        """
        let panelResp = try OrderedJSONDecoder.decode(RenderPanelResponse.self, from: panelRespJSON)
        #expect(!panelResp.skipped)
        #expect(panelResp.refID == "ch1/s1/p1")
        #expect(panelResp.imageData == pngData)
        #expect(panelResp.revisedPrompt == "dramatic ink lighting")
        #expect(panelResp.usage.imageCalls == 1)

        let storyboardRespJSON = """
        {
          "completed": false,
          "project": {"id": "proj-2", "title": "Demo", "characters": {"characters": []}, "usage": {"calls": 0, "imageCalls": 1, "inputTokens": 0, "outputTokens": 0, "totalTokens": 0}},
          "result": {
            "chapterId": "ch1",
            "rendered": 1,
            "skipped": 0,
            "failed": 1,
            "blocked": 1,
            "usage": {"calls": 0, "imageCalls": 1, "inputTokens": 0, "outputTokens": 0, "totalTokens": 0},
            "failures": [
              {"sceneId": "s1", "panelId": "p2", "error": "adapt: image generation blocked by content policy: SAFETY", "errorCode": "content_blocked"}
            ]
          },
          "images": [
            {"sceneId": "s1", "panelId": "p1", "refId": "ch1/s1/p1", "mimeType": "image/png", "dataBase64": "\(Self.samplePNGBase64)"}
          ],
          "error": "adapt: image generation blocked by content policy: SAFETY",
          "errorCode": "content_blocked"
        }
        """
        let storyboardResp = try OrderedJSONDecoder.decode(RenderStoryboardResponse.self, from: storyboardRespJSON)
        #expect(!storyboardResp.completed)
        #expect(storyboardResp.parsedErrorCode == .contentBlocked)
        #expect(storyboardResp.result.rendered == 1)
        #expect(storyboardResp.result.blocked == 1)
        #expect(storyboardResp.result.failures.count == 1)
        #expect(storyboardResp.result.failures[0].parsedErrorCode == .contentBlocked)
        #expect(storyboardResp.images.count == 1)
        #expect(storyboardResp.images[0].imageData == pngData)
    }

    @Test func adaptCoreErrorPredicatesAndReadableChineseMappings() {
        let budgetErr = CoreError("adapt: budget exceeded: image calls 2 reached limit 2")
        #expect(budgetErr.isBudgetExceeded)
        #expect(!budgetErr.isContentBlocked)
        #expect(budgetErr.errorDescription == AdaptErrorCode.budgetExceeded.readableMessage)

        // Safety block containing HTTP 403 must still map to contentBlocked, not comic Cloudflare 403.
        let blockedErr = CoreError("adapt: image generation blocked by content policy: HTTP 403 forbidden safety")
        #expect(blockedErr.isContentBlocked)
        #expect(!blockedErr.isBudgetExceeded)
        #expect(blockedErr.errorDescription == AdaptErrorCode.contentBlocked.readableMessage)

        let badJSONErr = CoreError("adapt: invalid storyboard JSON: scenes must be a non-empty array")
        #expect(badJSONErr.isInvalidStoryboard)
        #expect(badJSONErr.errorDescription == AdaptErrorCode.invalidStoryboard.readableMessage)

        let emptyErr = CoreError("adapt: chapter text is empty")
        #expect(emptyErr.isEmptyChapter)
        #expect(emptyErr.errorDescription == AdaptErrorCode.emptyChapter.readableMessage)

        let missingKey = CoreError("mobile: adapt text apiKey is required")
        #expect(missingKey.isInvalidAdaptArgument)
        #expect(missingKey.errorDescription == "请先配置有效的模型 API Key")

        let missingModel = CoreError("mobile: adapt image model is required")
        #expect(missingModel.isInvalidAdaptArgument)
        #expect(missingModel.errorDescription == "请先选择或填写模型名称")

        let badProtocol = CoreError("mobile: unsupported adapt text protocol \"bogus\"")
        #expect(badProtocol.isInvalidAdaptArgument)
        #expect(badProtocol.errorDescription?.contains("OpenAI Chat") == true)

        let badProvider = CoreError("mobile: unsupported adapt image provider \"bogus\"")
        #expect(badProvider.isInvalidAdaptArgument)
        #expect(badProvider.errorDescription?.contains("Gemini") == true)

        let badBase64 = CoreError("mobile: invalid adapt reference image base64: illegal base64")
        #expect(badBase64.isInvalidAdaptArgument)
        #expect(badBase64.errorDescription == "参考图数据格式无效")

        let badCheckpoint = CoreError("adapt: checkpoint chapter \"ch2\" does not match chapter \"ch1\"")
        #expect(badCheckpoint.isInvalidAdaptArgument)
        #expect(badCheckpoint.errorDescription?.contains("断点") == true)

        let missingPanel = CoreError("adapt: panel \"p99\" not found")
        #expect(missingPanel.isInvalidAdaptArgument)
        #expect(missingPanel.errorDescription == "找不到对应的分镜或画格")

        #expect(CoreError.readableAdapt(code: "budget_exceeded", message: nil) == AdaptErrorCode.budgetExceeded.readableMessage)
        #expect(CoreError.readableAdapt(code: "content_blocked", message: "raw") == AdaptErrorCode.contentBlocked.readableMessage)
        #expect(CoreError.readableAdapt(code: "canceled", message: nil) == "操作已取消")
        #expect(CoreError.readableAdapt(code: "error", message: "mobile: adapt project is required") == "改编请求参数无效,请检查配置后重试")
    }
}
