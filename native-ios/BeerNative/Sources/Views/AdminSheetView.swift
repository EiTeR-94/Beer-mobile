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
                BeerAdminReferentialsCard(
                    tab: $refTab,
                    styles: referentials?.styles ?? [],
                    hops: referentials?.hops ?? [],
                    flavors: referentials?.flavors ?? [],
                    filter: $refFilter,
                    newName: $refNewName,
                    onAdd: { Task { await addReferential() } },
                    onDelete: { name in Task { await deleteReferential(name) } }
                )
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showIPs) {
            InviteIPsSheetView(title: ipTitle, entries: ipEntries)
                .beerSheetChrome()
        }
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
            Text("\(inv.username ?? "—") · \(inv.checkins ?? 0) dégustation(s)")
                .font(.caption)
                .foregroundStyle(Theme.muted)

            if inv.redeemedAt != nil {
                inviteActivityLine(inv)
            }

            inviteDetailLines(inv)

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

    @ViewBuilder
    private func inviteActivityLine(_ inv: InviteItem) -> some View {
        let when = inv.lastUsedAt ?? inv.redeemedAt
        let ip = (inv.lastUsedAt != nil ? inv.lastUsedIp : inv.redeemIp) ?? ""
        HStack(alignment: .top, spacing: 6) {
            Text("Dernière activité · \(BeerFormatters.formatActivityAgo(when))\(ip.isEmpty ? "" : " · IP \(ip)")")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func inviteDetailLines(_ inv: InviteItem) -> some View {
        if inv.redeemedAt == nil {
            Text("En attente du 1er clic")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if let redeemed = inv.redeemedAt {
                    let ipPart = inv.redeemIp.map { " · IP \($0)" } ?? ""
                    inviteDetailRow("1er accès", "\(BeerFormatters.formatDate(redeemed))\(ipPart)")
                }
                if let rc = inv.redeemClient, rc.isKnown {
                    inviteDetailRow(
                        "Navigateur",
                        "\(rc.browser ?? "—") · \(rc.os ?? "—") · \(rc.device ?? "—")"
                    )
                }
                if let device = inv.deviceShort, !device.isEmpty {
                    inviteDetailRow("Appareil lié", device)
                }
                if let last = inv.lastUsedAt,
                   let redeemed = inv.redeemedAt,
                   last != redeemed,
                   let lc = inv.lastClient, lc.isKnown,
                   lc.browser != inv.redeemClient?.browser {
                    inviteDetailRow(
                        "Nav. récent",
                        "\(lc.browser ?? "—") · \(lc.os ?? "—")"
                    )
                }
                if inv.reactivationPending == true, let linkExp = inv.linkExpiresAt {
                    inviteDetailRow(
                        "Lien réactivation",
                        "expire \(BeerFormatters.formatDate(linkExp)) (10 min)"
                    )
                }
                if inv.permanent == true {
                    inviteDetailRow("Validité compte", "permanente")
                } else if let exp = inv.expiresAt, inv.reactivationPending != true {
                    inviteDetailRow("Validité compte", "jusqu'au \(BeerFormatters.formatDate(exp))")
                }
            }
        }
    }

    private func inviteDetailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            HStack(spacing: 6) {
                BeerCompactButton(title: "MDP", action: onSetPassword)
                if !isSelf {
                    BeerCompactButton(
                        title: user.isAdmin ? "Retirer admin" : "Promouvoir",
                        action: onToggleAdmin
                    )
                    BeerCompactButton(title: "Suppr.", destructive: true, action: onDelete)
                }
            }
            .padding(.top, 2)
        }
        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}