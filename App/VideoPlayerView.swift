import AetherEngine
import AVFoundation
import AVKit
import Combine
import NekularityKit
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
    /// The engine's own clock, read when the screen closes.
    private(set) var position: Double = 0
    private(set) var format = ""
    /// Playback speed the user picked; the engine clamps it to what this route can do.
    private(set) var rate: Float = 1
    /// What the source offers. Empty is a fact worth showing, not an error.
    private(set) var subtitleTracks: [TrackInfo] = []
    private(set) var activeSubtitleID: Int?
    /// Picture in Picture, for the route where the engine hands out an AVPlayer.
    @ObservationIgnored let pip = PiPController()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var watch: AnyCancellable?

    /// Called when playback starts and when the screen closes, so an episode
    /// that was opened and abandoned still lands in history.
    @ObservationIgnored var onProgress: ((Double, Double) -> Void)?

    func start(_ play: VideoPlay, from startPosition: Double) async {
        guard !started else { return }
        started = true
        guard let url = play.url.flatMap(URL.init(string:)) else {
            failure = "这个源没有给出可直接播放的地址"
            return
        }
        // PiP and background audio both need the audio session to be a playback
        // one; setting it here rather than at launch keeps a text-only reader from
        // taking over the speaker.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        do {
            let made = try AetherEngine()
            engine = made
            try await made.load(url: url, startPosition: startPosition,
                                options: LoadOptions(httpHeaders: play.headers ?? [:]))
            made.play()
            watch = made.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.sync(made) }
            }
            sync(made)
            onProgress?(made.currentTime, made.duration ?? 0)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// AetherEngine publishes its own state; mirroring it into observed
    /// properties is what lets this screen redraw.
    /// The last word on where this playback got to.
    func reportProgress() {
        onProgress?(position, duration ?? 0)
    }

    private func sync(_ engine: AetherEngine) {
        duration = engine.duration
        if engine.currentTime > 0 { position = engine.currentTime }
        format = String(describing: engine.videoFormat)
        subtitleTracks = engine.subtitleTracks
        activeSubtitleID = engine.activeSubtitleTrackIndex
        // Only the native route publishes an AVPlayer; on the software route the
        // engine decodes into its own layer, and PiP there needs
        // `softwarePiPSource` wiring that this screen does not have yet.
        pip.update(player: engine.currentAVPlayer)
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

    /// Speed, capped by what the engine says this route can do: 2× video, 3× audio.
    func setRate(_ value: Float) {
        rate = value
        engine?.setRate(value)
    }

    var maxRate: Float { engine?.maxSupportedRate ?? 2 }

    /// nil clears the subtitle, which is a choice and not a failure.
    func selectSubtitle(_ id: Int?) {
        guard let engine else { return }
        if let id {
            engine.selectSubtitleTrack(index: id)
            activeSubtitleID = id
        } else {
            engine.clearSubtitle()
            activeSubtitleID = nil
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
    /// Where to start, for a file the library already knows.
    var startPosition: Double = 0
    /// Called when the screen closes, with where playback got to.
    var onClose: ((Double, Double) -> Void)?
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
                if model.pip.isPossible {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.pip.toggle()
                        } label: {
                            Image(systemName: model.pip.isActive
                                  ? "pip.exit" : "pip.enter")
                        }
                        .accessibilityIdentifier("video.pip")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        onClose?(model.position, model.duration ?? 0)
                        model.stop()
                        dismiss()
                    }
                        .accessibilityIdentifier("video.close")
                }
            }
            .task { await model.start(play, from: startPosition) }
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
            speedMenu(engine)
            subtitleMenu(engine)
            if let duration = model.duration, duration > 0 {
                Text(Self.clock(duration)).font(.caption.monospacedDigit())
                    .accessibilityIdentifier("video.duration")
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

    /// Speeds the engine can actually hold. 2× is its cap for video, so offering
    /// 3× here would be offering a number that does nothing.
    private func speedMenu(_ engine: AetherEngine) -> some View {
        Menu {
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button {
                    model.setRate(rate)
                } label: {
                    if rate == model.rate {
                        Label(Self.speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.speedLabel(rate))
                    }
                }
            }
        } label: {
            Text(Self.speedLabel(model.rate)).font(.caption.monospacedDigit())
        }
        .accessibilityIdentifier("video.speed")
        .accessibilityValue(Self.speedLabel(model.rate))
    }

    /// A menu rather than a cycle button: a source with six subtitle tracks is
    /// common, and cycling to the sixth is not a control.
    @ViewBuilder
    private func subtitleMenu(_ engine: AetherEngine) -> some View {
        if !model.subtitleTracks.isEmpty {
            Menu {
                Button {
                    model.selectSubtitle(nil)
                } label: {
                    if model.activeSubtitleID == nil {
                        Label("关闭字幕", systemImage: "checkmark")
                    } else {
                        Text("关闭字幕")
                    }
                }
                ForEach(model.subtitleTracks, id: \.id) { track in
                    Button {
                        model.selectSubtitle(track.id)
                    } label: {
                        if track.id == model.activeSubtitleID {
                            Label(Self.trackLabel(track), systemImage: "checkmark")
                        } else {
                            Text(Self.trackLabel(track))
                        }
                    }
                }
            } label: {
                Image(systemName: model.activeSubtitleID == nil
                      ? "captions.bubble" : "captions.bubble.fill")
            }
            .accessibilityIdentifier("video.subtitles")
        }
    }

    private static func speedLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }

    /// The language if the container has one, else the track's own name, else its
    /// number: a menu of six rows all reading "字幕" is not a menu.
    private static func trackLabel(_ track: TrackInfo) -> String {
        if let language = track.language, !language.isEmpty {
            return Locale.current.localizedString(forIdentifier: language) ?? language
        }
        if !track.name.isEmpty { return track.name }
        return "字幕 \(track.id)"
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Picture in Picture around the engine's own AVPlayer.
///
/// The button only appears where the engine publishes an AVPlayer: asking for PiP
/// over a layer this screen does not own would open a window that shows nothing,
/// which is worse than no button.
@MainActor
@Observable
final class PiPController: NSObject, AVPictureInPictureControllerDelegate {
    private(set) var isPossible = false
    private(set) var isActive = false
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var attached: AVPlayer?

    func update(player: AVPlayer?) {
        guard let player else { return }
        // The engine re-emits the player on every reload; rebuilding the
        // controller each time would drop an open window.
        guard player !== attached else { return }
        attached = player
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPossible = false
            return
        }
        let made = AVPictureInPictureController(contentSource: .init(player: player))
        made.delegate = self
        controller = made
        isPossible = true
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: any Error) {
        Task { @MainActor in self.isActive = false }
    }
}
