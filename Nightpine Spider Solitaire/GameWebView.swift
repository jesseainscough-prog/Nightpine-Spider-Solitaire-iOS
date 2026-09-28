import SwiftUI
import WebKit

struct GameWebView: UIViewRepresentable {

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html"
        ) {
            webView.loadFileURL(
                indexURL,
                allowingReadAccessTo: indexURL.deletingLastPathComponent()
            )
        } else {
            print("ERROR: index.html was not found in the app bundle.")
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // The game manages its own UI and state.
    }
}
