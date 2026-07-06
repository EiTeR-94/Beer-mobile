import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppModel
    @State private var step = 1
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            BeerHeader(
                username: app.user,
                onHistory: { showHistory = true },
                onLogout: { Task { await app.logout() } }
            )

            if let banner = app.banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if !app.offline.items.isEmpty {
                Text("\(app.offline.items.count) dégustation(s) en attente de sync")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            BeerStepNav(step: $step)
            BeerWizardView(step: $step)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showHistory) {
            HistorySheetView()
                .environmentObject(app)
        }
    }
}