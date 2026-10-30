import NekularityKit
import Observation
import SwiftUI
import WebKit

/// Answers source UI requests (dialogs, choices, text, verification) with
/// SwiftUI sheets and alerts. One request is shown at a time; later ones
/// wait their turn.
@MainActor @Observable
final class PromptCenter: SourceUI {
    /// One request; `serial` makes consecutive prompts distinct sheets.
    struct Prompt: Identifiable {
        enum Kind {
            case dialog(title: String, content: String, actions: [DialogButton], reply: (Int?) -> Void)
            case text(title: String, imageURL: String?, error: String?, reply: (String?) -> Void)
            case choice(title: String, options: [String], initial: Int?, reply: (Int?) -> Void)
            case verify(VerificationSession)
        }
        let id: Int
        let kind: Kind
    }

    var current: Prompt?
    var toast: String?
    var loading: Set<Int64> = []

    @ObservationIgnored private var queue: [Prompt] = []
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private let cookies: CookieJars
    @ObservationIgnored private let userAgent: String
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored weak var host: CoreHost?

    init(cookies: CookieJars, userAgent: String) {
        self.cookies = cookies
        self.userAgent = userAgent
    }

    private func enqueue(_ kind: Prompt.Kind) {
        serial += 1
        let p = Prompt(id: serial, kind: kind)
        if current == nil { current = p } else { queue.append(p) }
    }

    /// Called when the shown prompt is answered or dismissed.
    func advance() {
        current = queue.isEmpty ? nil : queue.removeFirst()
    }

    // MARK: SourceUI

    func showMessage(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { toast = nil }
        }
    }

    func showDialog(title: String, content: String, actions: [DialogButton]) async -> Int? {
        await withCheckedContinuation { k in
            enqueue(.dialog(title: title, content: content, actions: actions, reply: { k.resume(returning: $0) }))
        }
    }

    func askText(title: String, imageURL: String?, errorMessage: String?) async -> String? {
        await withCheckedContinuation { k in
            enqueue(.text(title: title, imageURL: imageURL, error: errorMessage, reply: { k.resume(returning: $0) }))
        }
    }

    func askChoice(title: String, options: [String], initialIndex: Int?) async -> Int? {
        guard !options.isEmpty else { return nil }
        return await withCheckedContinuation { k in
            enqueue(.choice(title: title, options: options, initial: initialIndex, reply: { k.resume(returning: $0) }))
        }
    }

    func open(url: URL) { UIApplication.shared.open(url) }

    func showLoading(id: Int64) { loading.insert(id) }
    func hideLoading(id: Int64) { loading.remove(id) }

    func verify(_ challenge: Challenge) async -> String? {
        let session = VerificationSession(challenge: challenge, cookies: cookies, userAgent: userAgent)
        enqueue(.verify(session))
        let ua = await session.run()
        if case .verify(let s)? = current?.kind, s === session {
            advance()
        } else {
            queue.removeAll { if case .verify(let s) = $0.kind { s === session } else { false } }
        }
        return ua
    }
}

extension View {
    func sourcePrompts(_ center: PromptCenter) -> some View { modifier(PromptPresenter(center: center)) }
}

private struct PromptPresenter: ViewModifier {
    @Bindable var center: PromptCenter

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = center.toast {
                    Text(toast)
                        .font(.callout)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .overlay {
                if !center.loading.isEmpty {
                    ProgressView().controlSize(.large)
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .animation(.default, value: center.toast)
            .sheet(item: $center.current, onDismiss: nil) { prompt in
                PromptSheet(prompt: prompt, center: center)
                    .interactiveDismissDisabled(isVerify(prompt))
            }
    }

    func isVerify(_ p: PromptCenter.Prompt) -> Bool { if case .verify = p.kind { true } else { false } }
}

private struct PromptSheet: View {
    let prompt: PromptCenter.Prompt
    let center: PromptCenter
    @State private var text = ""
    @State private var answered = false

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { cancel() }
                    }
                }
        }
        .presentationDetents(detents)
        // A swipe-down counts as cancel.
        .onDisappear { if !answered { cancel() } }
    }

    private var detents: Set<PresentationDetent> {
        if case .verify = prompt.kind { [.large] } else { [.medium, .large] }
    }

    @ViewBuilder private var content: some View {
        switch prompt.kind {
        case .dialog(let title, let body, let actions, _):
            ScrollView {
                Text(body).frame(maxWidth: .infinity, alignment: .leading).padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                        Button(role: a.style == "danger" ? .destructive : nil) { reply(index: i) } label: {
                            Text(a.text).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(a.style == "filled" ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                        .controlSize(.large)
                    }
                }
                .padding()
            }
        case .text(let title, let imageURL, let error, _):
            Form {
                if let imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxHeight: 120)
                }
                TextField("输入", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { submitText() }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("确定") { submitText() } } }
        case .choice(let title, let options, let initial, _):
            List(Array(options.enumerated()), id: \.offset) { i, o in
                Button { reply(index: i) } label: {
                    HStack {
                        Text(o).foregroundStyle(.primary)
                        Spacer()
                        if i == initial { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        case .verify(let session):
            WebViewContainer(webView: session.webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("人机验证").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func reply(index: Int) {
        answered = true
        switch prompt.kind {
        case .dialog(_, _, _, let r), .choice(_, _, _, let r): r(index)
        default: break
        }
        center.advance()
    }

    private func submitText() {
        guard case .text(_, _, _, let r) = prompt.kind else { return }
        answered = true
        r(text)
        center.advance()
    }

    private func cancel() {
        guard !answered else { return }
        answered = true
        switch prompt.kind {
        case .dialog(_, _, _, let r), .choice(_, _, _, let r): r(nil)
        case .text(_, _, _, let r): r(nil)
        // run() returns nil and PromptCenter.verify advances.
        case .verify(let s): s.cancel(); return
        }
        center.advance()
    }
}

/// Type-erased button style, so one call site can pick a style at runtime.
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
