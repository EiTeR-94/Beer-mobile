import SwiftUI
import UIKit

struct AdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AdminUser] = []
    @State private var invites: [InviteItem] = []
    @State private var referentials: ReferentialsResponse?
    @State private var refTab = 0
    @State private var refFilter = ""
    @State private var refNewName = ""

    @State private var newUser = ""
    @State private var newPass = ""
    @State private var newAdmin = false
    @State private var userPasswords: [String: String] = [:]

    @State private var inviteLabel = ""
    @State private var inviteValidity = "7d"
    @State private var createdInviteURL: String?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var showIPs = false
    @State private var ipTitle = "IP invités"
    @State private var ipEntries: [InviteIpEntry] = []

    private let validityOptions: [(String, String)] = [
        ("24h", "24 heures"), ("48h", "48 heures"), ("7d", "7 jours"),
        ("14d", "14 jours"), ("30d", "30 jours"), ("90d", "90 jours"), ("permanent", "Permanent"),
    ]

    var body: some View {
        BeerOverlayScreen(
            title: "Administration",
            onClose: { dismiss() },
            trailing: [.ghost("↻ Actualiser") { Task { await reload() } }]
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(Theme.error) }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.ok) }

                BeerAdminSub(title: "Nouveau compte")
                BeerAdminCard {
                    VStack(spacing: 0) {
                        BeerField(label: "Identifiant", text: $newUser, placeholder: "ex. ney")
                        BeerField(label: "Mot de passe", text: $newPass, secure: true)
                            .padding(.top, 10)
                        Toggle("Administrateur", isOn: $newAdmin)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                            .tint(Theme.accent)
                            .padding(.top, 8)
                        BeerPrimaryButton(title: "Créer le compte", disabled: newUser.isEmpty || newPass.count < 6) {
                            Task { await createUser() }
                        }
                    }
                }

                BeerAdminSub(title: "Comptes")
                    ForEach(users) { u in
                        AdminUserCard(
                            user: u,
                            password: passwordBinding(for: u.username),
                            isSelf: u.username == app.user,
                            onSetPassword: { Task { await setPassword(u.username) } },
                            onToggleAdmin: {
                                Task { try? await app.api.adminSetAdmin(u.username, isAdmin: !u.isAdmin); await reload() }
                            },
                            onDelete: {
                                Task { try? await app.api.adminDeleteUser(u.username); await reload() }
                            }
                        )
                    }

                HStack(alignment: .center) {
                    Text("Invitations")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    BeerGhostButton("IP", action: openAllIPs)
                }
                .padding(.top, 12)

                Text("Compte + lien en un seul endroit. Lié au 1er appareil (4G OK ensuite). Cache vidé ? « Renvoyer l'accès » (lien 10 min). Révoquer = supprime le compte.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)

                BeerAdminCard {
                    VStack(spacing: 0) {
                        BeerField(label: "Nom de l'invité", text: $inviteLabel, placeholder: "ex. Paul")
                        BeerFilterLabel(label: "Validité") {
                            Picker("", selection: $inviteValidity) {
                                ForEach(validityOptions, id: \.0) { opt in Text(opt.1).tag(opt.0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.accent)
                        }
                        .padding(.top, 10)
                        BeerPrimaryButton(title: "Créer le lien", disabled: inviteLabel.count < 2) {
                            Task { await createInvite() }
                        }
                    }
                }
                    if let createdInviteURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lien à envoyer en privé :").font(.caption).foregroundStyle(Theme.muted)
                            Text(createdInviteURL).font(.caption2).textSelection(.enabled)
                            BeerSecondaryButton(title: "Copier le lien") {
                                UIPasteboard.general.string = createdInviteURL
                                message = "Lien copié"
                            }
                        }
                        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(invites) { inv in inviteCard(inv) }

                BeerAdminSub(title: "Maintenance")
                BeerSecondaryButton(title: "🧹 Nettoyer photos orphelines") {
                    Task {
                        do { message = try await app.api.adminCleanupPhotos(); errorMessage = nil }
                        catch let err { errorMessage = err.localizedDescription }
                    }
                }

                BeerAdminSub(title: "Référentiels")
                    Picker("Onglet", selection: $refTab) {
                        Text("Styles (\(referentials?.styles?.count ?? 0))").tag(0)
                        Text("Houblons (\(referentials?.hops?.count ?? 0))").tag(1)
                        Text("Saveurs (\(referentials?.flavors?.count ?? 0))").tag(2)
                    }
                    .pickerStyle(.segmented)
                    BeerField(label: "Filtrer…", text: $refFilter)
                    HStack {
                        BeerField(label: refAddLabel, text: $refNewName)
                        Button("+") { Task { await addReferential() } }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                    ForEach(filteredReferentials) { entry in
                        HStack {
                            Text(entry.name)
                            if entry.preset == true {
                                Text("preset").font(.caption2).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button("Suppr") { Task { await deleteReferential(entry.name) } }
                                .font(.caption).foregroundStyle(Theme.error)
                        }
                        .padding(8).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showIPs) {
            InviteIPsSheetView(title: ipTitle, entries: ipEntries)
                .beerSheetChrome()
        }
    }

    private var refAddLabel: String {
        switch refTab {
        case 1: return "Nouveau houblon"
        case 2: return "Nouvelle saveur"
        default: return "Nouveau style"
        }
    }

    private var filteredReferentials: [ReferentialEntry] {
        let list: [ReferentialEntry]
        switch refTab {
        case 1: list = referentials?.hops ?? []
        case 2: list = referentials?.flavors ?? []
        default: list = referentials?.styles ?? []
        }
        guard !refFilter.isEmpty else { return list }
        let q = BeerFormatters.normalizeSearch(refFilter)
        return list.filter { BeerFormatters.normalizeSearch($0.name).contains(q) }
    }

    @ViewBuilder
    private func inviteCard(_ inv: InviteItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(inv.label ?? "—").fontWeight(.semibold)
                Spacer()
                Text(inv.statusText).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.2)).foregroundStyle(Theme.accent).clipShape(Capsule())
            }
            Text("\(inv.username ?? "—") · \(inv.checkins ?? 0) dégustation(s)").font(.caption).foregroundStyle(Theme.muted)
            if let validity = inv.validityLabel, validity != "—" {
                Text("Type : \(validity)").font(.caption2).foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let log = inv.ipLog, !log.isEmpty {
                        inviteAction("IP") { openInviteIPs(inv) }
                    }
                    if let url = inv.url, inv.revokedAt == nil { inviteAction("Copier") { copyURL(url) } }
                    if inv.canExtend == true {
                        inviteAction("+24h") { Task { await extend(inv, "24h") } }
                        inviteAction("+48h") { Task { await extend(inv, "48h") } }
                        inviteAction("+7j") { Task { await extend(inv, "7d") } }
                        inviteAction("+30j") { Task { await extend(inv, "30d") } }
                        inviteAction("Perm.") { Task { await extend(inv, "permanent") } }
                    }
                    if inv.canReissue == true || inv.reactivationPending == true {
                        inviteAction("Renvoyer l'accès") { Task { await reissue(inv) } }
                    }
                    if inv.revokedAt == nil {
                        inviteAction("Révoquer", destructive: true) {
                            Task { try? await app.api.adminRevokeInvite(id: inv.id); await reload() }
                        }
                    }
                }
            }
        }
        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func inviteAction(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(destructive ? Color.clear : Theme.bg)
                .foregroundStyle(destructive ? Theme.error : Theme.text)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(destructive ? Theme.error.opacity(0.5) : Theme.border))
        }
    }

    private func openAllIPs() {
        var all: [InviteIpEntry] = []
        for inv in invites {
            all.append(contentsOf: inv.ipLog ?? [])
        }
        ipTitle = "IP invités"
        ipEntries = all
        showIPs = true
    }

    private func openInviteIPs(_ inv: InviteItem) {
        ipTitle = "IP — \(inv.label ?? "—")"
        ipEntries = inv.ipLog ?? []
        showIPs = true
    }

    private func passwordBinding(for username: String) -> Binding<String> {
        Binding(
            get: { userPasswords[username] ?? "" },
            set: { userPasswords[username] = $0 }
        )
    }

    private func copyURL(_ url: String) {
        UIPasteboard.general.string = url
        message = "Lien copié"
    }

    private func reload() async {
        users = (try? await app.api.adminUsers()) ?? []
        invites = (try? await app.api.adminInvites()) ?? []
        referentials = try? await app.api.adminReferentials()
    }

    private func createUser() async {
        do {
            try await app.api.adminCreateUser(username: newUser, password: newPass, isAdmin: newAdmin)
            newUser = ""; newPass = ""; newAdmin = false
            message = "Compte créé"; errorMessage = nil
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func setPassword(_ username: String) async {
        let pass = userPasswords[username] ?? ""
        guard pass.count >= 6 else { errorMessage = "Mot de passe trop court (6 min.)"; return }
        do {
            try await app.api.adminSetPassword(username, password: pass)
            userPasswords[username] = ""
            message = "Mot de passe mis à jour"
            errorMessage = nil
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func createInvite() async {
        do {
            let res = try await app.api.adminCreateInvite(label: inviteLabel, validity: inviteValidity)
            createdInviteURL = res.url
            inviteLabel = ""
            message = "Invitation créée"
            errorMessage = nil
            if let url = res.url { UIPasteboard.general.string = url }
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func extend(_ inv: InviteItem, _ validity: String) async {
        do {
            try await app.api.adminExtendInvite(id: inv.id, validity: validity)
            message = validity == "permanent" ? "Accès rendu permanent" : "Invitation prolongée"
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func reissue(_ inv: InviteItem) async {
        do {
            if let url = try await app.api.adminReissueInvite(id: inv.id) {
                UIPasteboard.general.string = url
                createdInviteURL = url
                message = "Lien de réactivation copié (10 min)"
            }
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func addReferential() async {
        let name = refNewName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else { return }
        do {
            switch refTab {
            case 1: try await app.api.adminAddHop(name)
            case 2: try await app.api.adminAddFlavor(name)
            default: try await app.api.adminAddStyle(name)
            }
            refNewName = ""
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func deleteReferential(_ name: String) async {
        do {
            switch refTab {
            case 1: try await app.api.adminDeleteHop(name)
            case 2: try await app.api.adminDeleteFlavor(name)
            default: try await app.api.adminDeleteStyle(name)
            }
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }
}

private struct AdminUserCard: View {
    let user: AdminUser
    @Binding var password: String
    let isSelf: Bool
    let onSetPassword: () -> Void
    let onToggleAdmin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(user.username).fontWeight(.semibold)
                if user.isAdmin {
                    Text("admin").font(.caption2).padding(4).background(Theme.accent.opacity(0.2)).clipShape(Capsule())
                }
                Spacer()
                Text("\(user.checkins) dégust.").font(.caption).foregroundStyle(Theme.muted)
            }
            BeerField(label: "Nouveau mot de passe", text: $password, secure: true)
            HStack {
                Button("MDP", action: onSetPassword).font(.caption)
                if !isSelf {
                    Button(user.isAdmin ? "Retirer admin" : "Promouvoir", action: onToggleAdmin).font(.caption)
                    Button("Suppr.", role: .destructive, action: onDelete).font(.caption)
                }
            }
        }
        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}