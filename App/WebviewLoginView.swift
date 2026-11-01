import NekularityKit
import SwiftUI
import WebKit

/// A source's own login page, shown in a sheet.
///
/// The page decides when the login is finished — that is the source's
/// checkStatus — so this view only draws the browser and the two ways out. The
/// session stores the cookies in the source's partition and reports back.
struct WebviewLoginView: View {
    let login: WebviewLogin
    let key: String
    let library: SourceLibrary
    let onFinish: (Result<Int, Error>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session: WebviewLoginSession?
    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    WebViewBox(webView: session.webView)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("登录 \(key)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        session?.cancel()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            guard !started else { return }
            started = true
            // The jars hold every source's cookies; this session writes into
            // the one partition its own key owns.
            guard let jars = library.cookieJars else {
                onFinish(.failure(CoreError("no cookie storage")))
                dismiss()
                return
            }
            let made = WebviewLoginSession(login: login, key: key,
                                           partition: CookiePartition.comic(key),
                                           core: library.core, jars: jars)
            session = made
            do {
                let count = try await made.run()
                onFinish(.success(count))
            } catch {
                onFinish(.failure(error))
            }
            dismiss()
        }
    }
}

/// Hosts a WKWebView that the session already built.
private struct WebViewBox: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
