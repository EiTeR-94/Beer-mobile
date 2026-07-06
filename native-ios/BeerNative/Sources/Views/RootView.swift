import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.isLoading {
                ZStack {
                    Theme.bg.ignoresSafeArea()
                    ProgressView("Chargement…")
                        .tint(Theme.accent)
                }
            } else if app.isLoggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .background(Theme.bg)
    }
}