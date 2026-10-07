import SwiftUI
import WebKit
import UIKit
import StoreKit

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
        webView.navigationDelegate = context.coordinator
        
        context.coordinator.webView = webView
        context.coordinator.startLifecycleObservers()

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

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        
        weak var webView: WKWebView?
        
        func startLifecycleObservers() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }
        
        @objc func appDidEnterBackground() {
            print("Spider Native: app entered background")
            guard let webView else { return }
            
            sendToJavaScript(
                webView: webView,
                type: "lifecycleSave",
                payload: ["reason": "background"]
            )
        }
        
        @objc func appDidBecomeActive() {
            print("Spider Native: app became active")
            guard let webView else { return }
            
            sendToJavaScript(
                webView: webView,
                type: "lifecycleResume",
                payload: ["reason": "active"]
            )
        }
        
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
                
            case "nativeReadyAck":
                let version = payload["bridgeVersion"] ?? "unknown"
                print("Spider Native: JavaScript bridge acknowledged version \(version)")
                
            case "gameReady":
                let gameVersion = payload["gameVersion"] ?? "unknown"
                print("Spider Native: game ready version \(gameVersion)")
                
                Task {
                    await StoreManager.shared.loadProducts()
                }
                
            case "showInterstitial":
                let reason = payload["reason"] as? String ?? "unknown"
                let requestId = payload["requestId"] as? String ?? ""

                print("Spider Native: interstitial requested (\(reason))")

                if let webView = self.webView {
                    sendToJavaScript(
                        webView: webView,
                        type: "adUnavailable",
                        payload: ["requestId": requestId]
                    )

                    print("Spider Native: adUnavailable sent for request \(requestId)")
                }

            case "adResponseProcessed":
                let status = payload["status"] as? String ?? "unknown"
                let requestId = payload["requestId"] as? String ?? "unknown"
                print("Spider Native: JavaScript processed \(status) for request \(requestId)")
                
            case "purchaseRemoveAds":
                let requestId = payload["requestId"] as? String ?? ""

                print("Spider Native: remove_ads purchase requested")

                Task {
                    let result = await StoreManager.shared.purchaseRemoveAds()

                    guard let webView = self.webView else { return }

                    let responseType: String

                    switch result {
                    case .purchased:
                        responseType = "purchaseFinished"

                    case .cancelled:
                        responseType = "purchaseCancelled"

                    case .pending:
                        responseType = "purchaseFailed"

                    case .failed:
                        responseType = "purchaseFailed"
                    }

                    sendToJavaScript(
                        webView: webView,
                        type: responseType,
                        payload: ["requestId": requestId]
                    )

                    print("Spider Native: \(responseType) sent for request \(requestId)")
                }
                
            case "restoreRemoveAds":
                let requestId = payload["requestId"] as? String ?? ""

                print("Spider Native: remove_ads restore requested")

                Task {
                    let hasEntitlement = await StoreManager.shared.hasRemoveAdsEntitlement()

                    guard let webView = self.webView else { return }

                    let responseType = hasEntitlement
                        ? "purchaseRestored"
                        : "purchaseFailed"

                    sendToJavaScript(
                        webView: webView,
                        type: responseType,
                        payload: ["requestId": requestId]
                    )

                    print("Spider Native: \(responseType) sent for request \(requestId)")
                }
                
            case "purchaseResponseProcessed":
                let status = payload["status"] as? String ?? "unknown"
                let requestId = payload["requestId"] as? String ?? "unknown"
                print("Spider Native: JavaScript processed \(status) for purchase \(requestId)")
                
            case "lifecycleSaveAck":
                let reason = payload["reason"] ?? "unknown"
                print("Spider Native: JavaScript lifecycle save acknowledged (\(reason))")
                
            case "lifecycleResumeAck":
                let reason = payload["reason"] ?? "unknown"
                print("Spider Native: JavaScript lifecycle resume acknowledged (\(reason))")
                
            default:
                print("Spider Native: unhandled message type \(type)")
            }
        }
    
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Spider Native: web view finished loading")
            
            sendToJavaScript(
                webView: webView,
                type: "nativeReady",
                payload: ["bridgeVersion": 1]
            )
        }
        
        func sendToJavaScript(
            webView: WKWebView,
            type: String,
            payload: [String: Any] = [:]
        ) {
            let message: [String: Any] = [
                "type": type,
                "payload": payload
            ]

            guard
                let data = try? JSONSerialization.data(withJSONObject: message),
                let json = String(data: data, encoding: .utf8)
            else {
                print("Spider Native: failed to encode JavaScript message")
                return
            }

            let script = """
            window.dispatchEvent(
                new CustomEvent('spiderNativeMessage', {
                    detail: \(json)
                })
            );
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    print("Spider Native: JavaScript error \(error)")
                }
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
