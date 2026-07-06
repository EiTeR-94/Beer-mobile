import SwiftUI
import UIKit

struct AdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AdminUser] = []
    @State private var invites: [InviteItem] = []
    @State private var newUser = ""
    @State private var newPass = ""
    @State private var newAdmin = false
    @State private var inviteLabel = ""
    @State private var inviteValidity = "7d"
    @State private var createdInviteURL: String?
    @State private var message: String?
    @State private var error: String?

    private let validityOptions: [(String, String)] = [
        ("24h", "24 heures"),
        ("48h", "48 heures"),
        ("7d", "7 jours"),
        ("14d", "14 jours"),
        ("30d", "30 jours"),
        ("90d", "90 jours"),
        ("permanent", "Permanent"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.error)
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(Theme.ok)
                    }

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
                    Text("Compte + lien en un seul endroit. Lié au 1er appareil. Cache vidé ? « Renvoyer l'accès » (10 min).")
                        .font(.caption).foregroundStyle(Theme.muted)

                    BeerField(label: "Nom invité", text: $inviteLabel, placeholder: "ex. Paul")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Validité").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Picker("Validité", selection: $inviteValidity) {
                            ForEach(validityOptions, id: \.0) { opt in
                                Text(opt.1).tag(opt.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }
                    BeerPrimaryButton(title: "Créer le lien", disabled: inviteLabel.count < 2) {
                        Task { await createInvite() }
                    }

                    if let createdInviteURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lien à envoyer en privé :")
                                .font(.caption).foregroundStyle(Theme.muted)
                            Text(createdInviteURL)
                                .font(.caption2)
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                            BeerSecondaryButton(title: "Copier le lien") {
                                UIPasteboard.general.string = createdInviteURL
                                message = "Lien copié"
                            }
                        }
                        .padding(10)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(invites) { inv in
                        inviteCard(inv)
                    }

                    BeerSecondaryButton(title: "🧹 Nettoyer photos orphelines") {
                        Task {
                            do {
                                message = try await app.api.adminCleanupPhotos()
                                error = nil
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
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

    @ViewBuilder
    private func inviteCard(_ inv: InviteItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(inv.label ?? "—").fontWeight(.semibold)
                Spacer()
                Text(inv.statusText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.2))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }

            Text("\(inv.username ?? "—") · \(inv.checkins ?? 0) dégustation(s)")
                .font(.caption).foregroundStyle(Theme.muted)

            if let validity = inv.validityLabel, validity != "—" {
                Text("Type : \(validity)").font(.caption2).foregroundStyle(Theme.muted)
            }
            if inv.permanent == true {
                Text("Validité compte : permanente").font(.caption2).foregroundStyle(Theme.muted)
            } else if let exp = inv.expiresAt {
                Text("Expire : \(exp)").font(.caption2).foregroundStyle(Theme.muted)
            }
            if let ip = inv.redeemIp ?? inv.lastUsedIp {
                Text("IP : \(ip)").font(.caption2).foregroundStyle(Theme.muted)
            }

            FlowLayout(spacing: 6) {
                if let url = inv.url, inv.revokedAt == nil {
                    inviteAction("Copier") { copyURL(url) }
                }
                if inv.canExtend == true {
                    inviteAction("+24h") { Task { await extend(inv, "24h") } }
                    inviteAction("+7j") { Task { await extend(inv, "7d") } }
                    inviteAction("Perm.") { Task { await extend(inv, "permanent") } }
                }
                if inv.canReissue == true || inv.reactivationPending == true {
                    inviteAction("Renvoyer") { Task { await reissue(inv) } }
                }
                if inv.revokedAt == nil {
                    inviteAction("Révoquer", destructive: true) {
                        Task { try? await app.api.adminRevokeInvite(id: inv.id); await reload() }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func inviteAction(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(destructive ? Color.clear : Theme.bg)
                .foregroundStyle(destructive ? Theme.error : Theme.text)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(destructive ? Theme.error.opacity(0.5) : Theme.border))
        }
    }

    private func copyURL(_ url: String) {
        UIPasteboard.general.string = url
        message = "Lien copié"
    }

    private func reload() async {
        users = (try? await app.api.adminUsers()) ?? []
        invites = (try? await app.api.adminInvites()) ?? []
    }

    private func createUser() async {
        do {
            try await app.api.adminCreateUser(username: newUser, password: newPass, isAdmin: newAdmin)
            newUser = ""; newPass = ""; newAdmin = false
            message = "Compte créé"
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createInvite() async {
        do {
            let res = try await app.api.adminCreateInvite(label: inviteLabel, validity: inviteValidity)
            createdInviteURL = res.url
            inviteLabel = ""
            message = "Invitation créée"
            error = nil
            if let url = res.url {
                UIPasteboard.general.string = url
            }
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func extend(_ inv: InviteItem, _ validity: String) async {
        do {
            try await app.api.adminExtendInvite(id: inv.id, validity: validity)
            message = validity == "permanent" ? "Accès rendu permanent" : "Invitation prolongée"
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reissue(_ inv: InviteItem) async {
        do {
            if let url = try await app.api.adminReissueInvite(id: inv.id) {
                UIPasteboard.general.string = url
                createdInviteURL = url
                message = "Lien de réactivation copié (10 min)"
            }
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}