import SwiftUI
import WebKit

/// Shell natif : charge la PWA Beer Log telle quelle (même HTML/CSS/JS que Safari).
struct BeerWebContainer: View {
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reloadToken = UUID()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            BeerWebView(
                url: ServerSettings.apiBase,
                reloadToken: reloadToken,
                isLoading: $isLoading,
                loadError: $loadError
            )
            .ignoresSafeArea(edges: .bottom)

            if isLoading, loadError == nil {
                loadingOverlay
            }
            if let loadError {
                errorOverlay(loadError)
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Theme.bg.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("🍺").font(.system(size: 44))
                ProgressView("Chargement…")
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🍺").font(.system(size: 40))
                Text("Impossible de joindre Beer Log")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Réessayer") {
                    loadError = nil
                    isLoading = true
                    reloadToken = UUID()
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.primaryGradient)
                .foregroundStyle(Theme.btnPrimaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
    }
}

struct BeerWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadError: $loadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(Self.standaloneUserScript)
        config.userContentController = controller
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 15.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 15 / 255, green: 20 / 255, blue: 25 / 255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        context.coordinator.webView = webView
        context.coordinator.load(url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.resetInitialLoad()
            isLoading = true
            loadError = nil
            context.coordinator.load(url)
        }
    }

    private static let standaloneUserScript = WKUserScript(
        source: """
        (function() {
          try {
            Object.defineProperty(navigator, 'standalone', {
              get: function() { return true; },
              configurable: true
            });
          } catch (e) {}
          var apply = function() {
            document.documentElement.classList.add('pwa-standalone');
          };
          if (document.documentElement) apply();
          else document.addEventListener('DOMContentLoaded', apply);
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var webView: WKWebView?
        var lastReloadToken = UUID()
        @Binding var isLoading: Bool
        @Binding var loadError: String?
        private var initialLoadDone = false

        init(isLoading: Binding<Bool>, loadError: Binding<String?>) {
            _isLoading = isLoading
            _loadError = loadError
        }

        func resetInitialLoad() {
            initialLoadDone = false
        }

        func load(_ url: URL) {
            webView?.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !initialLoadDone else { return }
            initialLoadDone = true
            isLoading = false
            loadError = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportError(error)
        }

        private func reportError(_ error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            guard !initialLoadDone else { return }
            initialLoadDone = true
            isLoading = false
            loadError = friendlyMessage(for: error)
        }

        private func friendlyMessage(for error: Error) -> String {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return "Pas de réseau — connecte-toi au Wi‑Fi ou au VPN Plexi."
                case NSURLErrorTimedOut:
                    return "Délai dépassé — vérifie ta connexion."
                default:
                    break
                }
            }
            return error.localizedDescription
        }

        @available(iOS 15.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}