import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("App native SwiftUI", systemImage: "swift")
                        .foregroundStyle(Theme.accent)
                    if let user = app.user {
                        Text(user)
                            .font(.title.bold())
                        if app.isAdmin {
                            Text("Administrateur")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    HStack {
                        Circle().fill(app.isOnline ? .green : .orange).frame(width: 10, height: 10)
                        Text(app.isOnline ? "En ligne" : "Hors ligne")
                    }
                    .font(.subheadline)
                }
                .beerCard()

                if !app.offline.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(app.offline.items.count) dégustation(s) en attente de sync")
                            .font(.headline)
                        Button("Synchroniser maintenant") {
                            Task { await app.syncPending() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                    .beerCard()
                }

                Text("API : \(ServerSettings.apiBaseString)")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)

                Button(role: .destructive) {
                    Task { await app.logout() }
                } label: {
                    Text("Déconnexion")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding(16)
            .padding(.top, 48)
            .background(Theme.bg)
            .navigationTitle("Compte")
        }
    }
}