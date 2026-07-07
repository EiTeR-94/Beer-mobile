import SwiftUI

@main
struct BeerNativeApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in
                    Task { await app.handleOpenURL(url) }
                }
        }
    }
}