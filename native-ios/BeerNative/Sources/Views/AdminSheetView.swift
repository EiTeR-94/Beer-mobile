import SwiftUI

struct AdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AdminUser] = []
    @State private var invites: [InviteItem] = []
    @State private var newUser = ""
    @State private var newPass = ""
    @State private var newAdmin = false
    @State private var inviteLabel = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nouveau compte").font(.headline)
                    BeerField(label: "Identifiant", text: $newUser)
                    BeerField(label: "Mot de passe", text: $newPass, secure: true)
                    Toggle("Administrateur", isOn: $newAdmin).tint(Theme.accent)
                    BeerPrimaryButton(title: "Créer le compte", disabled: newUser.isEmpty || newPass.count < 4) {
                        Task { await createUser() }
                    }

                    Text("Comptes").font(.headline).padding(.top, 8)
                    ForEach(users) { u in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(u.username).fontWeight(.semibold)
                                Text("\(u.checkins) dégust. · \(u.isAdmin ? "admin" : "user")")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if u.username != app.user {
                                Button(u.isAdmin ? "Retirer admin" : "Promouvoir") {
                                    Task { try? await app.api.adminSetAdmin(u.username, isAdmin: !u.isAdmin); await reload() }
                                }
                                .font(.caption)
                                Button("Suppr.", role: .destructive) {
                                    Task { try? await app.api.adminDeleteUser(u.username); await reload() }
                                }
                                .font(.caption)
                            }
                        }
                        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Text("Invitations").font(.headline).padding(.top, 8)
                    BeerField(label: "Nom invité", text: $inviteLabel, placeholder: "ex. Paul")
                    BeerPrimaryButton(title: "Créer le lien", disabled: inviteLabel.count < 2) {
                        Task { await createInvite() }
                    }
                    ForEach(invites) { inv in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(inv.label ?? "—").fontWeight(.medium)
                            if let url = inv.url { Text(url).font(.caption2).foregroundStyle(Theme.muted).textSelection(.enabled) }
                            Button("Révoquer", role: .destructive) { Task { try? await app.api.adminRevokeInvite(id: inv.id); await reload() } }
                                .font(.caption)
                        }
                        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    BeerSecondaryButton(title: "🧹 Nettoyer photos orphelines") {
                        Task {
                            message = try? await app.api.adminCleanupPhotos()
                        }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.ok) }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Administration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("↻") { Task { await reload() } } }
            }
            .task { await reload() }
        }
        .preferredColorScheme(.dark)
    }

    private func reload() async {
        users = (try? await app.api.adminUsers()) ?? []
        invites = (try? await app.api.adminInvites()) ?? []
    }

    private func createUser() async {
        do {
            try await app.api.adminCreateUser(username: newUser, password: newPass, isAdmin: newAdmin)
            newUser = ""; newPass = ""; newAdmin = false
            await reload()
        } catch { message = error.localizedDescription }
    }

    private func createInvite() async {
        do {
            try await app.api.adminCreateInvite(label: inviteLabel)
            inviteLabel = ""
            await reload()
        } catch { message = error.localizedDescription }
    }
}