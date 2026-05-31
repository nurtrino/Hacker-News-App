import SwiftUI
import WebKit

/// SwiftUI wrapper around a `WKWebView` configured for an ad-free, background-
/// capable YouTube experience. Exposes navigation state back to SwiftUI and
/// installs content-blocking rules + injected scripts on creation.
struct WebView: UIViewRepresentable {
    /// Drives navigation actions requested from SwiftUI (back/forward/reload).
    @Binding var action: WebViewAction?
    /// Reported back to SwiftUI so the toolbar can enable/disable buttons.
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool

    /// Spoofing a desktop-class Safari UA avoids YouTube's "Open in the app"
    /// interstitials while still serving a touch-friendly layout.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static let homeURL = URL(string: "https://www.youtube.com")!

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true

        let controller = WKUserContentController()
        if let inject = ContentBlockerStore.injectionScript() {
            controller.addUserScript(inject)
        }
        if let cosmetic = ContentBlockerStore.cosmeticScript() {
            controller.addUserScript(cosmetic)
        }
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black

        context.coordinator.webView = webView

        // Compile + attach the network-layer rule list asynchronously, then
        // load the home page once it is in place.
        Task { @MainActor in
            if let ruleList = await ContentBlockerStore.loadRuleList() {
                webView.configuration.userContentController.add(ruleList)
            }
            webView.load(URLRequest(url: Self.homeURL))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let action = action else { return }
        switch action {
        case .goBack where webView.canGoBack:
            webView.goBack()
        case .goForward where webView.canGoForward:
            webView.goForward()
        case .reload:
            webView.reload()
        case .home:
            webView.load(URLRequest(url: Self.homeURL))
        default:
            break
        }
        // Consume the action so it does not repeat on the next SwiftUI update.
        DispatchQueue.main.async { self.action = nil }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: WebView
        weak var webView: WKWebView?

        init(_ parent: WebView) {
            self.parent = parent
        }

        private func syncState(_ webView: WKWebView) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.isLoading = webView.isLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            syncState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncState(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            syncState(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            syncState(webView)
        }

        // Keep navigation inside the web view; open external schemes via the
        // system so things like the App Store or mail links still work.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme != "http", scheme != "https", scheme != "about" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Handle target="_blank" links by loading them in the same view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

/// One-shot navigation commands sent from SwiftUI into the `WKWebView`.
enum WebViewAction {
    case goBack
    case goForward
    case reload
    case home
}
