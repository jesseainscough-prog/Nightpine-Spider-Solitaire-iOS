import SwiftUI
import WebKit
import UIKit

struct GameWebView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        // Bridge expected by Spider Solitaire J.21.31
        configuration.userContentController.add(
            context.coordinator,
            name: "spiderNative"
        )

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

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

    final class Coordinator: NSObject, WKScriptMessageHandler {

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "spiderNative" else { return }

            guard
                let body = message.body as? [String: Any],
                let type = body["type"] as? String
            else {
                print("Spider Native: invalid message")
                return
            }

            let payload = body["payload"] as? [String: Any] ?? [:]

            switch type {

            case "haptic":
                let kind = payload["kind"] as? String ?? "light"
                performHaptic(kind)

            default:
                print("Spider Native: unhandled message type \(type)")
            }
        }

        private func performHaptic(_ kind: String) {
            switch kind {

            case "medium":
                UIImpactFeedbackGenerator(style: .medium)
                    .impactOccurred()

            case "strong", "heavy":
                UIImpactFeedbackGenerator(style: .heavy)
                    .impactOccurred()

            case "success":
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)

            case "error":
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.error)

            default:
                UIImpactFeedbackGenerator(style: .light)
                    .impactOccurred()
            }
        }
    }
}
