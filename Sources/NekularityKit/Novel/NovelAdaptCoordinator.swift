import Foundation
import Observation

/// Minimal Wave 4B Core surface needed by adaptation coordinators and tests.
public protocol NovelAdaptClient: Sendable {
    func adaptChapter(_ request: AdaptChapterRequest) async throws -> AdaptChapterResponse
    func renderPanel(_ request: RenderPanelRequest) async throws -> RenderPanelResponse
    func renderStoryboard(_ request: RenderStoryboardRequest) async throws -> RenderStoryboardResponse
}

extension CoreClient: NovelAdaptClient {}

/// Coordinator for Wave 4B novel-to-comic adaptation and static panel rendering.
///
/// Orchestrates Core's three adaptation entry points against `NovelAdaptStore`:
/// - Automatically resumes from saved `AdaptCheckpoint`s and clears them on
///   completion.
/// - Persists updated storyboards, cross-chapter `AdaptCharacterSheet`s, and
///   cumulative `AdaptUsage` atomically.
/// - Attaches locally stored style/character reference images to render calls
///   without ever writing AI API keys to disk.
/// - Caches rendered panel images and supports single-panel `ForceRerender`.
@MainActor
@Observable
public final class NovelAdaptCoordinator {
    public enum Phase: Sendable, Equatable {
        case idle
        case adapting(chapterID: String)
        case renderingPanel(chapterID: String, sceneID: String, panelID: String)
        case renderingStoryboard(chapterID: String)
        case completed(chapterID: String)
        case paused(chapterID: String, errorCode: AdaptErrorCode?, message: String)
        case failed(String)
    }

    public let projectID: String

    public private(set) var phase: Phase = .idle
    public private(set) var lastAdaptResponse: AdaptChapterResponse?
    public private(set) var lastRenderSummary: RenderSummary?
    public private(set) var lastError: String?
    public private(set) var lastErrorCode: AdaptErrorCode?

    @ObservationIgnored private let client: any NovelAdaptClient
    @ObservationIgnored private let store: NovelAdaptStore

    public init(projectID: String, client: any NovelAdaptClient, store: NovelAdaptStore) {
        self.projectID = projectID
        self.client = client
        self.store = store
    }

    // MARK: Workspace accessors

    public var workspace: NovelAdaptWorkspace? {
        store.workspace(id: projectID)
    }

    public var project: AdaptProject? {
        workspace?.project
    }

    public var characters: [AdaptCharacter] {
        project?.characters.characters ?? []
    }

    public func storyboard(for chapterID: String) -> AdaptStoryboard? {
        project?.storyboards[chapterID]
    }

    public func checkpoint(for chapterID: String) -> AdaptCheckpoint? {
        store.checkpoint(projectID: projectID, chapterID: chapterID)
    }

    public func panelImageData(chapterID: String, sceneID: String, panelID: String) -> Data? {
        store.loadPanelImageData(projectID: projectID, chapterID: chapterID, sceneID: sceneID, panelID: panelID)
    }

    public func panelImageURL(chapterID: String, sceneID: String, panelID: String) -> URL? {
        store.panelImageURL(projectID: projectID, chapterID: chapterID, sceneID: sceneID, panelID: panelID)
    }

    /// Ensures the workspace exists in `store`, creating it on first use.
    @discardableResult
    public func ensureProject(
        title: String,
        novelSourceKey: String? = nil,
        novelID: String? = nil,
        styleRef: AdaptStyleRef? = nil,
        budget: AdaptBudget = AdaptBudget()
    ) -> AdaptProject {
        if let existing = project {
            return existing
        }
        let created = AdaptProject(
            id: projectID,
            novelSourceKey: novelSourceKey,
            novelID: novelID,
            title: title,
            styleRef: styleRef,
            budget: budget
        )
        return store.upsertProject(created).project
    }

    // MARK: Chapter adaptation (storyboard + character sheet + checkpoint resume)

    /// Adapts one novel chapter into a storyboard, automatically resuming from a
    /// saved `AdaptCheckpoint` when `resumeFromCheckpoint` is true.
    @discardableResult
    public func adaptChapter(
        _ chapter: NovelChapter,
        content: NovelChapterContent,
        textConfig: AdaptTextConfig,
        maxChunkRunes: Int? = nil,
        resumeFromCheckpoint: Bool = true
    ) async throws -> AdaptChapterResponse {
        guard let currentProject = project else {
            let err = CoreError("adapt: nil project")
            recordFailure(err)
            throw err
        }

        let savedCheckpoint = resumeFromCheckpoint ? store.checkpoint(projectID: projectID, chapterID: chapter.id) : nil
        let options: AdaptOptions? = (maxChunkRunes != nil || savedCheckpoint != nil)
            ? AdaptOptions(maxChunkRunes: maxChunkRunes, checkpoint: savedCheckpoint)
            : nil

        phase = .adapting(chapterID: chapter.id)
        lastError = nil
        lastErrorCode = nil

        let request = AdaptChapterRequest(
            project: currentProject,
            chapter: chapter,
            content: content,
            text: textConfig,
            options: options
        )

        do {
            let response = try await client.adaptChapter(request)
            lastAdaptResponse = response

            store.performBatch {
                _ = store.upsertProject(response.project)
                if response.completed {
                    store.clearCheckpoint(projectID: projectID, chapterID: chapter.id)
                } else if let checkpoint = response.result?.checkpoint {
                    store.saveCheckpoint(checkpoint, projectID: projectID)
                }
            }

            if response.completed {
                phase = .completed(chapterID: chapter.id)
            } else {
                let code = response.parsedErrorCode
                let message = CoreError.readableAdapt(code: response.errorCode, message: response.error)
                lastError = message
                lastErrorCode = code
                phase = .paused(chapterID: chapter.id, errorCode: code, message: message)
            }
            return response
        } catch let error as CoreError where error.isCancelled {
            phase = .idle
            throw error
        } catch is CancellationError {
            phase = .idle
            throw CancellationError()
        } catch {
            recordFailure(error)
            throw error
        }
    }

    // MARK: Static comic panel rendering

    /// Renders all pending panels of `chapterID`, caching every returned image
    /// and persisting partial progress if rendering stops early.
    @discardableResult
    public func renderStoryboard(
        chapterID: String,
        imageConfig: AdaptImageConfig,
        options: AdaptRenderOptions = AdaptRenderOptions(),
        includeStoredReferences: Bool = true
    ) async throws -> RenderStoryboardResponse {
        guard let currentProject = project else {
            let err = CoreError("adapt: nil project")
            recordFailure(err)
            throw err
        }

        let mergedOptions = includeStoredReferences ? mergeStoredReferences(into: options) : options
        phase = .renderingStoryboard(chapterID: chapterID)
        lastError = nil
        lastErrorCode = nil

        let request = RenderStoryboardRequest(
            project: currentProject,
            chapterID: chapterID,
            image: imageConfig,
            options: mergedOptions
        )

        do {
            let response = try await client.renderStoryboard(request)
            lastRenderSummary = response.result

            try store.performBatch {
                _ = store.upsertProject(response.project)
                for image in response.images {
                    guard let bytes = image.imageData, !bytes.isEmpty else { continue }
                    _ = try store.savePanelImage(
                        projectID: projectID,
                        chapterID: chapterID,
                        sceneID: image.sceneID,
                        panelID: image.panelID,
                        refID: image.refID,
                        mimeType: image.mimeType,
                        data: bytes
                    )
                }
            }

            if response.completed {
                phase = .completed(chapterID: chapterID)
            } else {
                let rawCode = response.errorCode ?? response.result.failures.first?.errorCode
                let rawError = response.error ?? response.result.failures.first?.error
                let code = rawCode.flatMap(AdaptErrorCode.init(rawValue:))
                let message = CoreError.readableAdapt(code: rawCode, message: rawError)
                lastError = message
                lastErrorCode = code
                phase = .paused(chapterID: chapterID, errorCode: code, message: message)
            }
            return response
        } catch let error as CoreError where error.isCancelled {
            phase = .idle
            throw error
        } catch is CancellationError {
            phase = .idle
            throw CancellationError()
        } catch {
            recordFailure(error)
            throw error
        }
    }

    /// Renders (or skips if already done unless `forceRerender` is true) one panel
    /// and caches the rendered image bytes locally.
    @discardableResult
    public func renderPanel(
        chapterID: String,
        sceneID: String? = nil,
        panelID: String,
        imageConfig: AdaptImageConfig,
        options: AdaptRenderOptions = AdaptRenderOptions(),
        forceRerender: Bool = false,
        includeStoredReferences: Bool = true
    ) async throws -> RenderPanelResponse {
        guard let currentProject = project else {
            let err = CoreError("adapt: nil project")
            recordFailure(err)
            throw err
        }

        var mergedOptions = includeStoredReferences ? mergeStoredReferences(into: options) : options
        if forceRerender {
            mergedOptions.forceRerender = true
        }

        phase = .renderingPanel(chapterID: chapterID, sceneID: sceneID ?? "", panelID: panelID)
        lastError = nil
        lastErrorCode = nil

        let request = RenderPanelRequest(
            project: currentProject,
            chapterID: chapterID,
            sceneID: sceneID,
            panelID: panelID,
            image: imageConfig,
            options: mergedOptions
        )

        do {
            let response = try await client.renderPanel(request)
            try store.performBatch {
                _ = store.upsertProject(response.project)
                if !response.skipped, let bytes = response.imageData, !bytes.isEmpty {
                    let refID = response.refID ?? "\(chapterID)/\(response.sceneID)/\(response.panelID)"
                    let mime = response.mimeType ?? NovelAdaptStore.detectMIME(bytes)
                    _ = try store.savePanelImage(
                        projectID: projectID,
                        chapterID: chapterID,
                        sceneID: response.sceneID,
                        panelID: response.panelID,
                        refID: refID,
                        mimeType: mime,
                        data: bytes,
                        revisedPrompt: response.revisedPrompt
                    )
                }
            }
            phase = .completed(chapterID: chapterID)
            return response
        } catch let error as CoreError where error.isCancelled {
            phase = .idle
            throw error
        } catch is CancellationError {
            phase = .idle
            throw CancellationError()
        } catch {
            recordFailure(error)
            throw error
        }
    }

    /// Forces a single panel to be regenerated (`forceRerender: true`) and
    /// replaces its cached local image.
    @discardableResult
    public func rerenderPanel(
        chapterID: String,
        sceneID: String? = nil,
        panelID: String,
        imageConfig: AdaptImageConfig,
        options: AdaptRenderOptions = AdaptRenderOptions(),
        includeStoredReferences: Bool = true
    ) async throws -> RenderPanelResponse {
        try await renderPanel(
            chapterID: chapterID,
            sceneID: sceneID,
            panelID: panelID,
            imageConfig: imageConfig,
            options: options,
            forceRerender: true,
            includeStoredReferences: includeStoredReferences
        )
    }

    // MARK: Helpers

    private func mergeStoredReferences(into options: AdaptRenderOptions) -> AdaptRenderOptions {
        let stored = store.buildReferenceOptions(projectID: projectID)
        var merged = options

        if !stored.style.isEmpty {
            var seenIDs = Set(merged.styleReferences.compactMap(\.id))
            var combined = merged.styleReferences
            for ref in stored.style {
                if let id = ref.id, !id.isEmpty, seenIDs.contains(id) {
                    continue
                }
                if let id = ref.id, !id.isEmpty {
                    seenIDs.insert(id)
                }
                combined.append(ref)
            }
            merged.styleReferences = combined
        }

        if !stored.characters.isEmpty {
            var combined = merged.characterReferences
            for (key, refs) in stored.characters {
                var existing = combined[key] ?? []
                var seenIDs = Set(existing.compactMap(\.id))
                for ref in refs {
                    if let id = ref.id, !id.isEmpty, seenIDs.contains(id) {
                        continue
                    }
                    if let id = ref.id, !id.isEmpty {
                        seenIDs.insert(id)
                    }
                    existing.append(ref)
                }
                combined[key] = existing
            }
            merged.characterReferences = combined
        }

        return merged
    }

    private func recordFailure(_ error: Error) {
        if let coreError = error as? CoreError {
            let code: AdaptErrorCode?
            if coreError.isBudgetExceeded {
                code = .budgetExceeded
            } else if coreError.isContentBlocked {
                code = .contentBlocked
            } else if coreError.isInvalidStoryboard {
                code = .invalidStoryboard
            } else if coreError.isEmptyChapter {
                code = .emptyChapter
            } else {
                code = nil
            }
            let message = coreError.errorDescription ?? CoreError.readable(coreError.message)
            lastError = message
            lastErrorCode = code
            phase = .failed(message)
        } else {
            let message = error.localizedDescription
            lastError = message
            lastErrorCode = nil
            phase = .failed(message)
        }
    }
}
