import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabView {
            ScanTabView()
                .tabItem { Label("Scanner", systemImage: "barcode.viewfinder") }

            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock") }

            ProfileView()
                .tabItem { Label("Compte", systemImage: "person.circle") }
        }
        .background(Theme.bg)
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if let user = app.user {
                    HStack {
                        Circle().fill(app.isOnline ? .green : .orange).frame(width: 8, height: 8)
                        Text("Connecté · \(user)\(app.isAdmin ? " · admin" : "")")
                            .font(.caption.weight(.medium))
                        Spacer()
                        if !app.offline.items.isEmpty {
                            Text("\(app.offline.items.count) en attente")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.card)
                }
                if let banner = app.banner {
                    Text(banner)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 4)
        }
    }
}