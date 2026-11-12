import SwiftUI
import WebKit

/// Lese-Modus: die Notiz so, wie sie im PDF erscheint (`NoteHTML`), aber in
/// Bildschirmgrösse und auf dem Hintergrund des Editors. Links öffnen sich
/// im Browser.
struct NoteReadingView {
    let html: String
}

@MainActor
final class ReadingCoordinator: NSObject, WKNavigationDelegate {
    var lastHTML: String?

    func show(_ html: String, in webView: WKWebView) {
        guard html != lastHTML else { return }
        lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    nonisolated func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        MainActor.assumeIsolated {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                return decisionHandler(.allow)
            }
            #if os(iOS)
            UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
            decisionHandler(.cancel)
        }
    }

    static func makeWebView(delegate: ReadingCoordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = delegate
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #else
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        #endif
        return webView
    }
}

#if os(iOS)
extension NoteReadingView: UIViewRepresentable {
    func makeCoordinator() -> ReadingCoordinator { ReadingCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        ReadingCoordinator.makeWebView(delegate: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(html, in: webView)
    }
}
#else
extension NoteReadingView: NSViewRepresentable {
    func makeCoordinator() -> ReadingCoordinator { ReadingCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        ReadingCoordinator.makeWebView(delegate: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(html, in: webView)
    }
}
#endif
