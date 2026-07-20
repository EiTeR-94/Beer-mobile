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
    @State private var inviteEmail = ""
    @State private var inviteValidity = "7d"
    @State private var inviteCreating = false
    @State private var createdInviteURL: String?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var showIPs = false
    @State private var ipTitle = "IP invités"
    @State private var ipEntries: [InviteIpEntry] = []
    @State private var inviteToRevoke: InviteItem?
    @State private var inviteCheckinsTarget: InviteItem?
    @State private var showSettings = false
    @State private var feedbackUnread: Int = 0
    @State private var rpgPlayersCount: Int = 0
    @State private var rpgWithProfile: Int = 0
    /// Parité webapp : Comptes / Invités / Outils
    @State private var adminTab: AdminMainTab = .accounts
    @State private var showRpgAdmin = false

    private enum AdminMainTab: String, CaseIterable, Identifiable {
        case accounts, invites, tools
        var id: String { rawValue }
        var label: String {
            switch self {
            case .accounts: return "Comptes"
            case .invites: return "Invités"
            case .tools: return "Outils"
            }
        }
    }

    private let validityOptions: [(String, String)] = [
        ("24h", "24 heures"), ("48h", "48 heures"), ("7d", "7 jours"),
        ("14d", "14 jours"), ("30d", "30 jours"), ("90d", "90 jours"), ("permanent", "Permanent"),
    ]

    var body: some View {
        BeerOverlayScreen(
            title: "Administration",
            onClose: { dismiss() },
            trailing: [.ghost("⚙︎ Paramètres") { showSettings = true }]
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(Theme.error) }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.ok) }

                adminDashboard
                adminTabBar

                switch adminTab {
                case .accounts:
                    accountsTab
                case .invites:
                    invitesTab
                case .tools:
                    toolsTab
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showIPs) {
            InviteIPsSheetView(title: ipTitle, entries: ipEntries)
                .beerSheetChrome()
        }
        .sheet(item: $inviteCheckinsTarget) { inv in
            InviteCheckinsSheetView(invite: inv)
                .environmentObject(app)
                .beerSheetChrome()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
                .environmentObject(app)
        }
        .fullScreenCover(isPresented: $showRpgAdmin) {
            BeerquestAdminSheetView()
                .environmentObject(app)
        }
        .alert(
            "Révoquer l'invitation ?",
            isPresented: Binding(
                get: { inviteToRevoke != nil },
                set: { if !$0 { inviteToRevoke = nil } }
            ),
            presenting: inviteToRevoke
        ) { inv in
            Button("Annuler", role: .cancel) { inviteToRevoke = nil }
            Button("Révoquer", role: .destructive) {
                Task { await revokeInvite(inv) }
            }
        } message: { inv in
            Text("Le compte « \(inv.label ?? inv.username ?? "invité") » et ses dégustations seront supprimés.")
        }
    }

    // MARK: - Tabs (parité webapp)

    private var adminTabBar: some View {
        HStack(spacing: 6) {
            ForEach(AdminMainTab.allCases) { tab in
                Button {
                    adminTab = tab
                } label: {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(adminTab == tab ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            adminTab == tab
                                ? Theme.card.opacity(0.95)
                                : Theme.card.opacity(0.55)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    adminTab == tab ? Theme.accent : Theme.border,
                                    lineWidth: adminTab == tab ? 1.5 : 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var accountsTab: some View {
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
    }

    @ViewBuilder
    private var invitesTab: some View {
        HStack(alignment: .center) {
            Text("Invitations")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            BeerGhostButton("IP", action: openAllIPs)
        }

        Text("Lien + email (l'invité saisit l'email qu'il t'a donné). Lien 24 h si non utilisé. 1 appareil. « Renvoyer l'accès » = 10 min.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)

        BeerAdminCard {
            VStack(spacing: 0) {
                BeerField(label: "Nom de l'invité", text: $inviteLabel, placeholder: "ex. Paul")
                BeerField(label: "Email de l'invité", text: $inviteEmail, placeholder: "ex. paul@example.com")
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(.top, 10)
                BeerSelectField(
                    label: "Validité du compte",
                    value: inviteValidity,
                    options: validityOptions,
                    onSelect: { inviteValidity = $0 }
                )
                .padding(.top, 10)
                BeerPrimaryButton(
                    title: inviteCreating ? "Génération…" : "Créer le lien",
                    disabled: inviteLabel.count < 2 || inviteEmail.isEmpty || !inviteEmail.contains("@") || inviteCreating,
                    busy: inviteCreating
                ) {
                    Task { await createInvite() }
                }
            }
        }
        if let url = createdInviteURL {
            InviteLinkResultCard(
                url: url,
                onCopy: { copyCreatedInviteLink() },
                onClose: { createdInviteURL = nil }
            )
        }
        ForEach(invites) { inv in inviteCard(inv) }
    }

    @ViewBuilder
    private var toolsTab: some View {
        BeerAdminSub(title: "Outils")
        VStack(spacing: 8) {
            BeerPrimaryButton(title: "⚔ Admin Beerquest") {
                showRpgAdmin = true
            }
            BeerSecondaryButton(title: "🧹 Nettoyer photos orphelines") {
                Task {
                    do { message = try await app.api.adminCleanupPhotos(); errorMessage = nil }
                    catch let err { errorMessage = err.localizedDescription }
                }
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
            if inv.redeemedAt != nil, inv.linkActive != true {
                Text("Lien d'invitation consommé — plus utilisable (session = appareil lié)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }

            if inv.redeemedAt != nil {
                inviteActivityLine(inv)
            }

            inviteDetailLines(inv)

            if let validity = inv.validityLabel, validity != "—" {
                Text("Type : \(validity)").font(.caption2).foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Dégustations toujours dispo si compte lié (même 0 pour empty state)
                    if inv.redeemedAt != nil || (inv.checkins ?? 0) > 0 {
                        inviteAction("Dégustations") { inviteCheckinsTarget = inv }
                    }
                    if let log = inv.ipLog, !log.isEmpty {
                        inviteAction("IP") { openInviteIPs(inv) }
                    }
                    // Copier uniquement si le lien join est encore actif (pas après activation)
                    if let url = inv.url, !url.isEmpty, inv.revokedAt == nil,
                       inv.linkActive != false {
                        inviteAction("Copier") { copyInviteURL(url) }
                    }
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
                            inviteToRevoke = inv
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
            VStack(alignment: .leading, spacing: 3) {
                Text("En attente du 1er clic")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                if let hint = inv.emailHint, !hint.isEmpty {
                    inviteDetailRow("Email", hint)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if let hint = inv.emailHint, !hint.isEmpty {
                    inviteDetailRow("Email", hint)
                }
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

    private func copyCreatedInviteLink() {
        guard let url = createdInviteURL else { return }
        UIPasteboard.general.string = url
        createdInviteURL = nil
        app.showToast("Lien copié", variant: .success, durationMs: 2800)
    }

    private func copyInviteURL(_ url: String) {
        UIPasteboard.general.string = url
        if createdInviteURL == url { createdInviteURL = nil }
        app.showToast("Lien copié", variant: .success, durationMs: 2800)
    }

    // MARK: - Dashboard

    private var adminDashboard: some View {
        let activeInvites = invites.filter { $0.active == true || ($0.redeemedAt != nil && $0.revokedAt == nil) }.count
        let totalCheckins = users.reduce(0) { $0 + $1.checkins }
        let appV = app.appVersion
        let webV = app.serverVersion.isEmpty ? "—" : app.serverVersion
        let latest = app.latestIosVersion
        let outdated = app.needsAppUpdate

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📊 Tableau de bord")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("Beer Quest")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.accent)
            }

            // Versions webapp vs IPA
            VStack(alignment: .leading, spacing: 8) {
                Text("Versions")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    versionPill(title: "Webapp", value: webV, tone: .web)
                    versionPill(title: "Cette IPA", value: "\(appV) (\(app.appBuild))", tone: outdated ? .warn : .ok)
                    if let latest, !latest.isEmpty {
                        versionPill(title: "Dernière IPA", value: latest, tone: .info)
                    }
                }
                if outdated {
                    Link(destination: app.portalURL) {
                        HStack(spacing: 6) {
                            Text("⬆️")
                            Text("IPA ancienne — télécharger la dernière ici")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Text("→")
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(10)
                        .background(Theme.accent.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(12)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                dashTile("👥", "\(users.count)", "Comptes")
                dashTile("✉️", "\(activeInvites)", "Invités actifs")
                dashTile("🍺", "\(totalCheckins)", "Check-ins")
                dashTile("⚔", "\(rpgWithProfile)", "RPG profils")
                dashTile("💬", "\(feedbackUnread)", "Feedback")
                dashTile("🏅", "\(rpgPlayersCount)", "Joueurs RPG")
            }
        }
        .padding(.bottom, 4)
    }

    private enum VersionTone { case web, ok, warn, info }

    private func versionPill(title: String, value: String, tone: VersionTone) -> some View {
        let border: Color = {
            switch tone {
            case .web: return Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.45)
            case .ok: return Color.green.opacity(0.45)
            case .warn: return Theme.accent.opacity(0.55)
            case .info: return Theme.border
            }
        }()
        let fg: Color = {
            switch tone {
            case .web: return Color(red: 0.38, green: 0.65, blue: 0.98)
            case .ok: return Color.green
            case .warn: return Theme.accent
            case .info: return Theme.muted
            }
        }()
        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(fg)
            Text(value)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.fieldBg.opacity(0.7))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func dashTile(_ ico: String, _ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(ico).font(.system(size: 14))
            Text(v).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            Text(l).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reload() async {
        var fromCache = false

        if let live = try? await app.api.adminUsers() {
            users = live
            app.cache.save(live, name: CacheKey.adminUsers)
        } else if let cached = app.cache.load([AdminUser].self, name: CacheKey.adminUsers) {
            users = cached
            fromCache = true
        }

        if let live = try? await app.api.adminInvites() {
            invites = live
            app.cache.save(live, name: CacheKey.adminInvites)
        } else if let cached = app.cache.load([InviteItem].self, name: CacheKey.adminInvites) {
            invites = cached
            fromCache = true
        }

        if let live = try? await app.api.adminReferentials() {
            referentials = live
            app.cache.save(live, name: CacheKey.adminReferentials)
        } else if referentials == nil, let cached = app.cache.load(ReferentialsResponse.self, name: CacheKey.adminReferentials) {
            referentials = cached
            fromCache = true
        }

        // Dashboard extras (best-effort, ne casse pas l’admin si offline)
        if let stats = await app.api.adminFeedbackStats() {
            feedbackUnread = stats.unread ?? 0
        }
        if let players = try? await app.api.adminRpgPlayers() {
            rpgPlayersCount = players.count
            rpgWithProfile = players.filter { $0.hasProfile == true || ($0.xp ?? 0) > 0 || ($0.level ?? 1) > 1 }.count
        }
        await app.refreshMobileVersions()
        if app.serverVersion.isEmpty {
            app.serverVersion = (try? await app.api.version()) ?? app.serverVersion
        }

        if fromCache {
            errorMessage = nil
            message = "Données en cache — \(app.networkStatus.label.lowercased())"
        }
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
        guard !inviteCreating else { return }
        let label = inviteLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count >= 2 else {
            app.showToast("Nom trop court (2 car. min.)", variant: .warn)
            return
        }
        guard email.contains("@") else {
            app.showToast("Email invité requis", variant: .warn)
            return
        }
        inviteCreating = true
        app.showToast(
            "Lien en cours de génération…",
            variant: .info,
            label: "Invitation",
            durationMs: 120_000
        )
        defer { inviteCreating = false }
        do {
            let res = try await app.api.adminCreateInvite(label: label, email: email, validity: inviteValidity)
            app.hideToast()
            createdInviteURL = res.url
            inviteLabel = ""
            inviteEmail = ""
            message = nil
            errorMessage = nil
            await reload()
            app.showToast(
                "Lien créé — copie-le maintenant",
                variant: .success,
                label: "Invitation",
                durationMs: 4200
            )
        } catch let err {
            app.hideToast()
            errorMessage = err.localizedDescription
            app.showToast(err.localizedDescription, variant: .error, durationMs: 4200)
        }
    }

    private func extend(_ inv: InviteItem, _ validity: String) async {
        do {
            try await app.api.adminExtendInvite(id: inv.id, validity: validity)
            message = validity == "permanent" ? "Accès rendu permanent" : "Invitation prolongée"
            await reload()
        } catch let err { errorMessage = err.localizedDescription }
    }

    private func revokeInvite(_ inv: InviteItem) async {
        inviteToRevoke = nil
        do {
            try await app.api.adminRevokeInvite(id: inv.id)
            if createdInviteURL == inv.url { createdInviteURL = nil }
            await reload()
            app.showToast("Invitation révoquée", variant: .success, durationMs: 3200)
        } catch let err {
            app.showToast(err.localizedDescription, variant: .error, durationMs: 4200)
        }
    }

    private func reissue(_ inv: InviteItem) async {
        do {
            if let url = try await app.api.adminReissueInvite(id: inv.id) {
                createdInviteURL = url
                await reload()
                app.showToast(
                    "Lien de réactivation prêt (10 min)",
                    variant: .success,
                    label: "Invitation",
                    durationMs: 4200
                )
            }
        } catch let err {
            app.showToast(err.localizedDescription, variant: .error, durationMs: 4200)
        }
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

private struct InviteLinkResultCard: View {
    let url: String
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("Lien à envoyer en privé :")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 26)
                        .background(Theme.bg)
                        .overlay(Circle().stroke(Theme.border))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }
            Text(url)
                .font(.caption2)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            BeerSecondaryButton(title: "Copier le lien", action: onCopy)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AdminUserCard: View {
    let user: AdminUser
    @Binding var password: String
    let isSelf: Bool
    let onSetPassword: () -> Void
    let onToggleAdmin: () -> Void
    let onDelete: () -> Void

    /// Fraîcheur d’activité (ambre → muet), sans arc-en-ciel.
    private var activityTone: Color {
        guard let raw = user.lastCheckinAt, !raw.isEmpty else { return Theme.muted.opacity(0.7) }
        // ISO-ish dates: plus c’est récent, plus c’est chaud
        let prefix = String(raw.prefix(10))
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: prefix) else { return Theme.muted }
        let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 999
        if days <= 2 { return Theme.accent }
        if days <= 14 { return Theme.accent.opacity(0.75) }
        if days <= 45 { return Theme.muted }
        return Theme.muted.opacity(0.55)
    }

    private var activityLabel: String {
        guard let raw = user.lastCheckinAt, !raw.isEmpty else { return "Jamais de check-in" }
        return "Dernière activité \(BeerFormatters.formatDate(raw))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(user.username).fontWeight(.semibold).foregroundStyle(Theme.text)
                        if user.isAdmin {
                            Text("admin")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                        if isSelf {
                            Text("toi")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().stroke(Theme.border))
                        }
                    }
                    Text(activityLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(activityTone)
                }
                Spacer()
            }

            // Détails type invités (stats compactes)
            HStack(spacing: 6) {
                metaChip("🍺 \(user.checkins)", "dégust.")
                metaChip("📷 \(user.photos ?? 0)", "photos")
                metaChip("🎨 \(user.stylesCount ?? 0)", "styles")
                metaChip("🏭 \(user.breweriesCount ?? 0)", "brass.")
            }

            if let created = user.createdAt, !created.isEmpty {
                Text("Créé \(BeerFormatters.formatDate(created))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted.opacity(0.85))
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
        .padding(12)
        .background(Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(user.isAdmin ? Theme.accent.opacity(0.35) : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metaChip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.fieldBg.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}