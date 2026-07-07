import SwiftUI

@main
struct BeerNativeApp: App {
    @StateObject private var app = AppModel()

    init() {
        URLProtocol.registerClass(PlexiIPv4URLProtocol.self)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in
                    Task { await app.handleOpenURL(url) }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await app.handleOpenURL(url) }
                }
        }
    }
}