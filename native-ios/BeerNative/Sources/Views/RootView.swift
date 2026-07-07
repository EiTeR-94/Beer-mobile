import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            Group {
                if app.isLoading {
                    ZStack {
                        Theme.bg.ignoresSafeArea()
                        VStack(spacing: 14) {
                            Text("🍺").font(.system(size: 44))
                            ProgressView("Chargement…")
                                .tint(Theme.accent)
                        }
                    }
                } else if app.isLoggedIn {
                    MainView()
                } else {
                    LoginView()
                }
            }
            .background(Theme.bg)
            .dismissKeyboardOnTap()

            ToastOverlay(toast: app.toast, onDismiss: { app.hideToast() })
        }
    }
}