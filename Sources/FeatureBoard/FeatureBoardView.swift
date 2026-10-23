import SwiftUI
import WebKit

/// Presents the hosted board within the app. The provider calls YOUR authenticated
/// backend to obtain a short-lived board token. Never put a board server secret here.
@MainActor
public struct FeatureBoardView: View {
    private let url: URL
    private let allowLocalhostHTTP: Bool
    private let tokenProvider: @MainActor () async throws -> String
    @State private var isLoading = true
    @State private var failed = false
    @State private var retryID = UUID()

    public init(
        url: URL,
        allowLocalhostHTTP: Bool = false,
        tokenProvider: @escaping @MainActor () async throws -> String
    ) {
        self.url = url
        self.allowLocalhostHTTP = allowLocalhostHTTP
        self.tokenProvider = tokenProvider
    }

    public var body: some View {
        ZStack {
            BoardWebView(
                url: url,
                allowLocalhostHTTP: allowLocalhostHTTP,
                tokenProvider: tokenProvider,
                onLoading: { isLoading = $0 },
                onFailure: { failed = true; isLoading = false }
            )
            .id(retryID)

            if isLoading && !failed {
                ProgressView("Loading feedback…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            if failed {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text("Couldn't open feedback").font(.headline)
                    Text("Check your connection and account access, then try again.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        failed = false
                        isLoading = true
                        retryID = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
            }
        }
    }
}

@MainActor
private struct BoardWebView: UIViewRepresentable {
    let url: URL
    let allowLocalhostHTTP: Bool
    let tokenProvider: @MainActor () async throws -> String
    let onLoading: (Bool) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "featureBoard")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.keyboardDismissMode = .interactive
        context.coordinator.webView = webView
        if context.coordinator.isConfiguredURLSafe {
            webView.load(URLRequest(url: url))
        } else {
            Task { @MainActor in onFailure() }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Keep the provider current after the host app's state changes.
        context.coordinator.parent = self
        if context.coordinator.loadedURL != url {
            context.coordinator.invalidate()
            context.coordinator.loadedURL = url
            if context.coordinator.isConfiguredURLSafe {
                uiView.load(URLRequest(url: url))
            } else {
                uiView.stopLoading()
                Task { @MainActor in onFailure() }
            }
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "featureBoard")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: BoardWebView
        var loadedURL: URL
        weak var webView: WKWebView?
        private var tokenTask: Task<Void, Never>?
        private var generation = UUID()

        init(parent: BoardWebView) {
            self.parent = parent
            self.loadedURL = parent.url
        }

        var isConfiguredURLSafe: Bool {
            guard let host = parent.url.host?.lowercased(),
                  parent.url.user == nil, parent.url.password == nil,
                  parent.url.query == nil, parent.url.fragment == nil else { return false }
            if parent.url.scheme?.lowercased() == "https" { return true }
            return parent.allowLocalhostHTTP && parent.url.scheme == "http"
                && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        }

        private func matchesOrigin(_ url: URL?) -> Bool {
            guard isConfiguredURLSafe, let url,
                  url.user == nil, url.password == nil else { return false }
            func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
            return url.scheme?.lowercased() == parent.url.scheme?.lowercased()
                && url.host?.lowercased() == parent.url.host?.lowercased()
                && port(url) == port(parent.url)
        }

        func invalidate() {
            generation = UUID()
            tokenTask?.cancel()
            tokenTask = nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "featureBoard", message.frameInfo.isMainFrame,
                  matchesOrigin(message.frameInfo.request.url), matchesOrigin(webView?.url),
                  let body = message.body as? [String: Any], body["type"] as? String == "tokenRequired",
                  tokenTask == nil else { return }
            let currentGeneration = generation
            tokenTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { if generation == currentGeneration { tokenTask = nil } }
                do {
                    let token = try await parent.tokenProvider()
                    try Task.checkCancellation()
                    guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          token.count <= 8_192, !token.contains("\r"), !token.contains("\n") else {
                        throw URLError(.userAuthenticationRequired)
                    }
                    guard generation == currentGeneration, let webView, matchesOrigin(webView.url) else { return }
                    // Arguments are serialized by WebKit. The token is never interpolated into source.
                    webView.callAsyncJavaScript(
                        "window.FeatureBoard.setToken(token);",
                        arguments: ["token": token], in: nil, in: .page
                    ) { [weak self] result in
                        guard let self, generation == currentGeneration else { return }
                        if case .failure = result { parent.onFailure() }
                    }
                } catch is CancellationError {
                    // A dismissed/reloaded board must not receive a stale account token.
                } catch {
                    if generation == currentGeneration { parent.onFailure() }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // New windows, subframes, external origins, and custom schemes cannot access the bridge.
            decisionHandler(action.targetFrame?.isMainFrame == true && matchesOrigin(action.request.url) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.isForMainFrame && matchesOrigin(response.response.url) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            invalidate()
            parent.onLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.onLoading(false) }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failUnlessCancelled(error) }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failUnlessCancelled(error) }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            invalidate()
            parent.onFailure()
        }

        private func failUnlessCancelled(_ error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { parent.onFailure() }
        }
    }
}
