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
    /// The picture's own clock, ~10 Hz. `state` does not change while playing, so
    /// anything drawn against time has to read this rather than `position`.
    private(set) var time: Double = 0
    private(set) var cues: [SubtitleCue] = []
    /// Picture in Picture, for the route where the engine hands out an AVPlayer.
    @ObservationIgnored let pip = PiPController()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var watch: AnyCancellable?
    @ObservationIgnored private var clockWatch: AnyCancellable?
    @ObservationIgnored private var positionWatch: AnyCancellable?

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
                                options: LoadOptions(httpHeaders: play.requestHeaders))
            made.play()
            watch = made.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.sync(made) }
            }
            // Separate object on purpose: subscribing to the engine's own publisher
            // would re-render the whole screen ten times a second.
            clockWatch = made.clock.$sourceTime.sink { [weak self] value in
                Task { @MainActor [weak self] in self?.time = value }
            }
            // `position` was only updated when the engine published a state change,
            // so closing a player mid-episode reported wherever the last change was.
            positionWatch = made.clock.$currentTime.sink { [weak self] value in
                guard value > 0 else { return }
                Task { @MainActor [weak self] in self?.position = value }
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
        cues = engine.subtitleCues
        // Only the native route publishes an AVPlayer; on the software route the
        // engine decodes into its own layer, and PiP there needs
        // `softwarePiPSource` wiring that this screen does not have yet.
        pip.update(player: engine.currentAVPlayer, software: engine.softwarePiPSource)
        // Same player, same layer, but the position moved: the window's scrubber
        // reads these snapshots.
        pip.refresh()
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
        clockWatch = nil
        positionWatch = nil
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
    /// The provider and show this belongs to. Empty means "no show identity", and
    /// then no opening is offered rather than one guessed from the episode title.
    ///
    /// Declared before `startPosition` on purpose: a memberwise initialiser takes
    /// its arguments in declaration order, and every call site reads
    /// provider → show → position.
    var provider: String = ""
    var showTitle: String = ""
    /// Where to start, for a file the library already knows.
    var startPosition: Double = 0
    /// Called when the screen closes, with where playback got to.
    var onClose: ((Double, Double) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(IntroStore.self) private var intros
    @State private var model = VideoPlayerModel()
    @State private var danmaku: [DanmakuComment] = []
    @State private var showsDanmaku = true
    @State private var importingDanmaku = false
    @State private var danmakuNote: String?

    var body: some View {
        NavigationStack {
            Group {
                if let engine = model.engine {
                    AetherPlayerSurface(engine: engine)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay { subtitleLayer }
                        .overlay { danmakuLayer }
                        .overlay(alignment: .bottom) { bottomBar(engine) }
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
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("video.close")
                }
            }
            .task { await model.start(play, from: startPosition) }
            .alert(danmakuNote ?? "", isPresented: Binding(get: { danmakuNote != nil },
                                                          set: { if !$0 { danmakuNote = nil } })) {
                Button("好") { danmakuNote = nil }
            }
            .fileImporter(isPresented: $importingDanmaku,
                          allowedContentTypes: [.xml, .json, .plainText]) { result in
                loadDanmaku(result)
            }
            .onDisappear {
                // Button dismissal and the sheet's swipe gesture share one exit.
                // Capture progress before stopping the engine resets its clock.
                onClose?(model.position, model.duration ?? 0)
                model.stop()
            }
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
            danmakuMenu
            if let duration = model.duration, duration > 0 {
                Text(PlaybackProgress.clock(duration)).font(.caption.monospacedDigit())
                    .accessibilityIdentifier("video.duration")
                    // The picture's own clock, read by VoiceOver as "played so
                    // far" and by the interface test as evidence that frames are
                    // advancing: a duration alone exists as soon as decoding
                    // starts, even if the picture then stalls on its first frame.
                    .accessibilityValue(PlaybackProgress.clock(model.time))
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

    /// The transport, with the skip-the-opening button on top of it when there is
    /// an opening to skip.
    @ViewBuilder
    private func bottomBar(_ engine: AetherEngine) -> some View {
        VStack(spacing: 10) {
            if let mark = introMark, mark.contains(model.position) {
                Button {
                    Task { await engine.seek(to: mark.end) }
                } label: {
                    Label("跳过片头", systemImage: "forward.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("video.skipIntro")
            }
            transport(engine)
        }
    }

    private var danmakuMenu: some View {
        Menu {
            Toggle("显示弹幕", isOn: $showsDanmaku)
            Button("加载弹幕文件…") { importingDanmaku = true }
            if !danmaku.isEmpty {
                Button("清除弹幕", role: .destructive) { danmaku = [] }
            }
            Divider()
            if !provider.isEmpty, !showTitle.isEmpty {
                Button("把当前位置标为片头起点") {
                    intros.mark(provider: provider, title: showTitle,
                                start: model.position, end: model.position + 90)
                }
                if introMark != nil {
                    Button("清除片头标记", role: .destructive) {
                        intros.forget(provider: provider, title: showTitle)
                    }
                }
            }
        } label: {
            Image(systemName: danmaku.isEmpty ? "text.bubble" : "text.bubble.fill")
        }
        .accessibilityIdentifier("video.danmaku")
        .accessibilityValue(danmaku.isEmpty ? "无弹幕" : "\(danmaku.count) 条")
    }

    private var introMark: IntroMark? {
        guard !provider.isEmpty, !showTitle.isEmpty else { return nil }
        return intros.mark(provider: provider, title: showTitle)
    }

    /// Only the recent window is drawn, and only when the toggle is on. Drawing
    /// thousands of lines over a video is how playback stutters.
    @ViewBuilder
    private var danmakuLayer: some View {
        if showsDanmaku, !danmaku.isEmpty {
            let active = DanmakuParser.active(danmaku, at: model.time)
            VStack {
                // Position, not the comment's own id: the same words can be sent
                // twice at the same second, and duplicate ids make SwiftUI drop
                // one of them.
                ForEach(Array(active.filter { $0.placement == .top }.enumerated()), id: \.offset) { _, comment in
                    danmakuLine(comment)
                }
                Spacer()
                ForEach(Array(active.filter { $0.placement != .top }.suffix(6).enumerated()), id: \.offset) { _, comment in
                    danmakuLine(comment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
            .allowsHitTesting(false)
        }
    }

    /// Text cues from the engine, drawn as an overlay.
    ///
    /// Bitmap cues (PGS/DVB) are deliberately not drawn here: they arrive as images
    /// with their own geometry, and the software route already composites them into
    /// the frames it renders. Drawing an image cue badly would be worse than leaving
    /// it to the path that already does it.
    @ViewBuilder
    private var subtitleLayer: some View {
        let lines = model.cues
            .filter { $0.startTime <= model.time && model.time < $0.endTime }
            .compactMap(\.text)
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            VStack {
                Spacer()
                VStack(spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            // A caption over a bright frame needs its own ground; a
                            // shadow alone disappears on a white sky.
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 96)
            }
            .allowsHitTesting(false)
        }
    }

    private func danmakuLine(_ comment: DanmakuComment) -> some View {
        Text(comment.text)
            .font(.callout.weight(.medium))
            .foregroundStyle(Color(hex: comment.color))
            .shadow(color: .black.opacity(0.8), radius: 2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reads a file the user picked. Both formats are accepted because both are
    /// what downloaders produce, and asking which one it is would be a question
    /// with no good answer.
    private func loadDanmaku(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = url.pathExtension.lowercased() == "json"
                ? DanmakuParser.parse(json: text)
                : DanmakuParser.parse(xml: text)
            if parsed.isEmpty {
                danmakuNote = "这个文件里没有读到弹幕"
            } else {
                danmaku = parsed
                danmakuNote = "已加载 \(parsed.count) 条"
            }
        } catch {
            danmakuNote = error.localizedDescription
        }
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
    @ObservationIgnored private var software: SoftwarePiPSource?
    /// The PiP window asks these synchronously, from whatever thread AVKit is on.
    /// A stored property of this class is out of reach there, and `assumeIsolated`
    /// would trap if the assumption were ever wrong, so the two answers live in a
    /// box that can be read from any thread. The main actor writes it on every
    /// engine publish; the window reads whatever was last written.
    nonisolated let transport = TransportSnapshot()

    /// Would tear down a running window if it were recreated per publish.
    @ObservationIgnored private var nativeLayer: AVPlayerLayer?

    /// The native route hands out an `AVPlayer`; the software route decodes into its
    /// own layer. Both can show a window, through two different content sources.
    func update(player: AVPlayer?, software: SoftwarePiPSource?) {
        if let player {
            updateNative(player)
            return
        }
        guard let software else { return }
        // Rebuilding around the same layer would tear down a window that is open.
        guard software !== self.software else { return }
        self.software = software
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPossible = false
            return
        }
        let made = AVPictureInPictureController(
            contentSource: .init(sampleBufferDisplayLayer: software.layer, playbackDelegate: self))
        made.delegate = self
        controller = made
        isPossible = true
        refresh()
    }

    /// Re-reads the transport answers. Called on every engine publish, so the
    /// window's scrubber follows playback.
    func refresh() {
        guard let software else { return }
        transport.store(range: software.timeRange(), paused: software.isPaused)
    }

    private func updateNative(_ player: AVPlayer) {
        // The engine re-emits the player on every reload; rebuilding the
        // controller each time would drop an open window.
        guard player !== attached else { return }
        attached = player
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPossible = false
            return
        }
        // The content source takes a layer, not a player: a player has to be given
        // to a layer before it has anything to show in the window.
        let layer = AVPlayerLayer(player: player)
        nativeLayer = layer
        let made = AVPictureInPictureController(contentSource: .init(playerLayer: layer))
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

/// The two answers AVKit asks synchronously from its own thread.
///
/// A lock rather than an actor because the question is synchronous: waiting for a
/// main-actor hop to answer `pictureInPictureControllerTimeRangeForPlayback` is not
/// possible, and answering with a value read without one would be a data race on a
/// 48-byte struct.
final class TransportSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var range = CMTimeRange(start: .zero, duration: .indefinite)
    private var paused = true

    var current: (range: CMTimeRange, paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (range, paused)
    }

    func store(range: CMTimeRange, paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.range = range
        self.paused = paused
    }
}

/// The four transport answers a sample-buffer PiP window asks for.
///
/// The engine keeps the frame timeline, so these are forwarded rather than
/// computed here: answering from this screen's own clock would drift from what the
/// window is showing.
extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                setPlaying playing: Bool) {
        Task { @MainActor in self.software?.setPlaying(playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController) -> CMTimeRange {
        // Read on the calling thread: the source answers from the engine, and
        // hopping would answer a stale range to a synchronous question.
        transport.current.range
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController) -> Bool {
        transport.current.paused
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // Nothing to lay out: the layer is the engine's and it sizes itself.
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        let seconds = skipInterval.seconds
        Task { @MainActor in
            self.software?.skip(by: seconds.isFinite ? seconds : 0)
        }
        // Answered here rather than inside the hop: carrying the completion handler
        // across an isolation boundary is what the compiler objected to, and the
        // window does not need it to mean "the skip landed" — it asks for the new
        // time range next, which is refreshed from the engine.
        completionHandler()
    }
}
