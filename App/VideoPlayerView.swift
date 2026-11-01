import AetherEngine
import Combine
import Observation
import SwiftUI

/// Plays one episode with AetherEngine.
///
/// The engine is created once per screen and kept for as long as the sheet is
/// open: it owns a decode pipeline, so making a new one per redraw would tear
/// the picture down. The provider's headers go into `LoadOptions` because many
/// origins check `Referer` or `User-Agent` on every segment, not just the
/// playlist.
@MainActor
@Observable
final class VideoPlayerModel {
    private(set) var engine: AetherEngine?
    private(set) var failure: String?
    private(set) var phase = "idle"
    private(set) var duration: Double?
    private(set) var format = ""
    @ObservationIgnored private var started = false
    @ObservationIgnored private var watch: AnyCancellable?

    func start(_ play: VideoPlay) async {
        guard !started else { return }
        started = true
        guard let url = play.url.flatMap(URL.init(string:)) else {
            failure = "这个源没有给出可直接播放的地址"
            return
        }
        do {
            let made = try AetherEngine()
            engine = made
            try await made.load(url: url,
                                options: AetherEngine.LoadOptions(httpHeaders: play.headers ?? [:]))
            made.play()
            watch = made.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.sync(made) }
            }
            sync(made)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// AetherEngine publishes its own state; mirroring it into observed
    /// properties is what lets this screen redraw.
    private func sync(_ engine: AetherEngine) {
        duration = engine.duration
        format = String(describing: engine.videoFormat)
        switch engine.state {
        case .idle: phase = "idle"
        case .loading: phase = "loading"
        case .playing: phase = "playing"
        case .paused: phase = "paused"
        case .seeking: phase = "seeking"
        case .ended: phase = "ended"
        case .error(let message): phase = "error"; failure = message
        }
    }

    func stop() {
        watch = nil
        engine?.stop()
        engine = nil
    }
}

/// The player screen: the engine's surface, a title bar and a transport.
///
/// A video that plays only in full screen and cannot be paused is an unfinished
/// screen, so the pause control is here rather than left to a system overlay.
struct VideoPlayerView: View {
    let title: String
    let play: VideoPlay
    @Environment(\.dismiss) private var dismiss
    @State private var model = VideoPlayerModel()

    var body: some View {
        NavigationStack {
            Group {
                if let engine = model.engine {
                    AetherPlayerSurface(engine: engine)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { transport(engine) }
                } else if let failure = model.failure {
                    ContentUnavailableView {
                        Label("无法播放", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure)
                    }
                } else {
                    ProgressView("正在打开…")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { model.stop(); dismiss() }
                        .accessibilityIdentifier("video.close")
                }
            }
            .task { await model.start(play) }
            .onDisappear { model.stop() }
        }
    }

    private func transport(_ engine: AetherEngine) -> some View {
        HStack(spacing: 18) {
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: model.phase == "playing" ? "pause.fill" : "play.fill")
                    .imageScale(.large)
            }
            .accessibilityIdentifier("video.playPause")
            if let duration = model.duration, duration > 0 {
                Text(Self.clock(duration)).font(.caption.monospacedDigit())
            }
            if !model.format.isEmpty {
                Text(model.format).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
