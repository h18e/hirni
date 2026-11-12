import HirniKit
import WebKit

/// Lädt eine Webseite unsichtbar und holt ihren Hauptinhalt als Markdown
/// (siehe `WebPageMarkdown`). Seiten, die erst ein Skript aufbaut, erhalten
/// nach dem Laden einen Moment Zeit.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1400), configuration: configuration)
    }()
    private var loaded: CheckedContinuation<Void, Error>?

    struct Failure: LocalizedError {
        var errorDescription: String? { "Die Seite liess sich nicht laden." }
    }

    static func load(_ url: URL) async throws -> (title: String, markdown: String) {
        let loader = WebPageLoader()
        return try await loader.run(url)
    }

    private func run(_ url: URL) async throws -> (title: String, markdown: String) {
        webView.navigationDelegate = self
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(25))
            self?.finish(.failure(Failure()))
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.load(URLRequest(url: url))
        }
        try? await Task.sleep(for: .seconds(1))
        guard let json = try await webView.evaluateJavaScript(WebPageMarkdown.extractionScript) as? String else { throw Failure() }
        let page = try WebPageMarkdown.page(fromJSON: json)
        return (page.title.trimmingCharacters(in: .whitespacesAndNewlines), WebPageMarkdown.markdown(from: page.root))
    }

    private func finish(_ result: Result<Void, Error>) {
        loaded?.resume(with: result)
        loaded = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finish(.success(())) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { finish(.failure(Failure())) }
    }
}
