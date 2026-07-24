import SwiftUI

/// Admin Beerquest — style RPG taverne (Joueurs + Feedback, parité webapp).
struct BeerquestAdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var players: [RpgAdminPlayer] = []
    @State private var rpgFlags: RpgAdminFlags?
    @State private var settingsBusy = false
    @State private var loading = true
    @State private var error: String?
    @State private var selectedUser: String?
    @State private var filter = ""
    @State private var flagsLine = "Registre des aventuriers"

    /// Joueurs / Contrôle (kill-switch) / Feedback
    @State private var adminTab: BqAdminTab = .control
    @State private var feedbackItems: [AdminFeedbackItem] = []
    @State private var feedbackStats: AdminFeedbackStats?
    @State private var feedbackLoading = false
    @State private var feedbackError: String?
    @State private var feedbackUnreadOnly = false
    @State private var feedbackStatusFilter = "" // "" | open | done | rejected
    @State private var feedbackToDelete: AdminFeedbackItem?
    @State private var feedbackBusyId: Int?
    @State private var resolveTarget: FeedbackResolveTarget?
    @State private var didPickInitialTab = false

    private enum BqAdminTab: String, CaseIterable, Identifiable {
        case players, control, feedback
        var id: String { rawValue }
        var label: String {
            switch self {
            case .players: return "Joueurs"
            case .control: return "Contrôle"
            case .feedback: return "Feedback"
            }
        }
    }

    private var filtered: [RpgAdminPlayer] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return players }
        return players.filter {
            ($0.username ?? "").lowercased().contains(q)
                || ($0.title ?? "").lowercased().contains(q)
                || ($0.classKey ?? "").lowercased().contains(q)
        }
    }

    private var unreadCount: Int { feedbackStats?.unread ?? 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fond RPG
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.07, blue: 0.05), Theme.bg, Color(red: 0.06, green: 0.08, blue: 0.1)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    tabBar
                    switch adminTab {
                    case .players:
                        searchBar
                        listBody
                    case .control:
                        controlBody
                    case .feedback:
                        feedbackToolbar
                        feedbackBody
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await reload() }
            .sheet(item: Binding(
                get: { selectedUser.map { UserKey(id: $0) } },
                set: { selectedUser = $0?.id }
            )) { key in
                RpgAdminPlayerDetailView(username: key.id) {
                    selectedUser = nil
                    Task { await reload() }
                }
                .environmentObject(app)
                .preferredColorScheme(.dark)
            }
            .alert(
                "Supprimer ce feedback ?",
                isPresented: Binding(
                    get: { feedbackToDelete != nil },
                    set: { if !$0 { feedbackToDelete = nil } }
                ),
                presenting: feedbackToDelete
            ) { item in
                Button("Annuler", role: .cancel) { feedbackToDelete = nil }
                Button("Supprimer", role: .destructive) {
                    Task { await deleteFeedback(item) }
                }
            } message: { item in
                Text(String((item.message ?? "").prefix(120)))
            }
            .sheet(item: $resolveTarget) { target in
                FeedbackResolveSheet(target: target) { reply in
                    resolveTarget = nil
                    Task { await resolveFeedback(id: target.id, status: target.status, reply: reply) }
                } onCancel: {
                    resolveTarget = nil
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.medium])
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("⚔ REGISTRE")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .tracking(1.2)
                Text("Admin Beerquest")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(flagsLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task {
                    if adminTab == .players { await reload() }
                    else { await loadFeedback() }
                }
            } label: {
                Text("↻")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            BeerGhostButton("Fermer") { dismiss() }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(BqAdminTab.allCases) { tab in
                Button {
                    adminTab = tab
                    if tab == .feedback {
                        Task { await loadFeedback() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.label)
                            .font(.system(size: 13, weight: .bold))
                        if tab == .feedback, unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
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
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// Onglet kill-switch : libellés clairs, pas de jargon RPG/UI.
    private var controlBody: some View {
        let gameOn = rpgFlags?.enabled == true
        let invitesOn = rpgFlags?.allowInvites == true
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Interrupteurs serveur")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Sans rebuild. Réservé admin · Wi‑Fi / VPN maison.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)

                controlSwitchCard(
                    title: "Beerquest (tout le monde)",
                    subtitle: gameOn
                        ? "Le jeu est actif : XP, quêtes, grimoire pour les joueurs autorisés."
                        : "Le jeu est coupé : plus d’XP ni de grimoire. Le carnet de bières reste.",
                    isOn: gameOn,
                    onColor: gameOn ? Color.green : Theme.error,
                    enabled: !settingsBusy
                ) { newVal in
                    Task { await patchSetting("enabled", value: newVal) }
                }

                controlSwitchCard(
                    title: "Inclure les invités",
                    subtitle: invitesOn
                        ? "Les comptes invite_* peuvent aussi jouer à Beerquest."
                        : "Les invités n’ont que le carnet (pas de jeu).",
                    isOn: invitesOn,
                    onColor: Theme.accent,
                    enabled: !settingsBusy && gameOn
                ) { newVal in
                    Task { await patchSetting("allow_invites", value: newVal) }
                }

                if !gameOn {
                    Text("Beerquest est OFF — ouvre cet onglet pour le rallumer. Le menu ⚔ reste toujours dispo pour l’admin.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.yellow.opacity(0.9))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Text("Par joueur : onglet Joueurs → fiche → ON / OFF / Auto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
        }
    }

    private func controlSwitchCard(
        title: String,
        subtitle: String,
        isOn: Bool,
        onColor: Color,
        enabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOn ? onColor : Theme.muted.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { onChange($0) }
            ))
            .labelsHidden()
            .tint(onColor)
            .disabled(!enabled)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? onColor.opacity(0.4) : Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(enabled ? 1 : 0.55)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text("🔍").font(.system(size: 13))
            TextField("Chercher un aventurier…", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Feedback (parité webapp)

    private var feedbackToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await loadFeedback() }
                } label: {
                    Text("↻ Actualiser")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await markAllFeedbackRead() }
                } label: {
                    Text("Tout marquer lu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(unreadCount == 0)

                Spacer(minLength: 0)
            }

            // Case à cocher (comme la webapp)
            Button {
                feedbackUnreadOnly.toggle()
                Task { await loadFeedback() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: feedbackUnreadOnly ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(feedbackUnreadOnly ? Theme.accent : Theme.muted)
                    Text("Non lus seulement")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Filtre statut
            Picker("Statut", selection: $feedbackStatusFilter) {
                Text("Tous les statuts").tag("")
                Text("En cours").tag("open")
                Text("Mis en place").tag("done")
                Text("Refusés").tag("rejected")
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .onChange(of: feedbackStatusFilter) { _ in
                Task { await loadFeedback() }
            }

            let s = feedbackStats
            Text("\(s?.unread ?? 0) non lu(s) · \(s?.open ?? 0) en cours · \(s?.done ?? 0) faits · \(s?.rejected ?? 0) refusés · \(s?.total ?? feedbackItems.count) total")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var feedbackBody: some View {
        if feedbackLoading && feedbackItems.isEmpty {
            Spacer()
            ProgressView("Chargement feedback…").tint(Theme.accent)
            Spacer()
        } else if let feedbackError, feedbackItems.isEmpty {
            Spacer()
            Text(feedbackError).foregroundStyle(Theme.error).padding()
            Spacer()
        } else if feedbackItems.isEmpty {
            Spacer()
            Text(feedbackUnreadOnly ? "Aucun feedback non lu." : "Aucun feedback.")
                .foregroundStyle(Theme.muted)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(feedbackItems, id: \.stableId) { item in
                        feedbackCard(item)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
            }
        }
    }

    private func feedbackCard(_ f: AdminFeedbackItem) -> some View {
        let unread = f.adminRead != true
        let when = BeerFormatters.formatDate(f.createdAt)
        var line1: [String] = []
        if !when.isEmpty { line1.append(when) }
        if let ip = f.clientIp, !ip.isEmpty { line1.append(ip) }
        var line2: [String] = []
        let device = f.deviceLine
        if !device.isEmpty { line2.append(device) }
        if let v = f.appVersion, !v.isEmpty { line2.append("v\(v)") }
        if let lv = f.metaRpgLevel { line2.append(lv) }
        let busy = feedbackBusyId == f.id
        let border: Color = {
            if f.isDone { return Color.green.opacity(0.45) }
            if f.isRejected { return Theme.error.opacity(0.45) }
            if unread { return Theme.accent.opacity(0.45) }
            return Theme.border
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(f.username ?? "—")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.text)
                        if f.isInvite == true { adminPill("invité", .invite) }
                        if unread { adminPill("nouveau", .off) }
                        adminPill(f.displayStatus, f.isDone ? .on : (f.isRejected ? .off : .muted))
                    }
                    Text(f.displayCategory)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
            }

            Text(f.message ?? "")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if let reply = f.adminReply, !reply.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Réponse")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    Text(reply)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fieldBg.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !line1.isEmpty {
                Text(line1.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            if !line2.isEmpty {
                Text(line2.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }

            // Case à cocher « Lu »
            Button {
                Task { await toggleFeedbackRead(f) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: (f.adminRead == true) ? "checkmark.square.fill" : "square")
                        .foregroundStyle((f.adminRead == true) ? Theme.accent : Theme.muted)
                    Text("Lu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)

            HStack(spacing: 8) {
                if f.isOpen {
                    Button {
                        if let id = f.id {
                            resolveTarget = FeedbackResolveTarget(
                                id: id,
                                status: "done",
                                title: "Marquer comme mis en place",
                                hint: "Le joueur verra ta note au prochain login.",
                                requireReply: false,
                                original: f.message ?? ""
                            )
                        }
                    } label: {
                        Text("✓ Fait")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    Button {
                        if let id = f.id {
                            resolveTarget = FeedbackResolveTarget(
                                id: id,
                                status: "rejected",
                                title: "Refuser le feedback",
                                hint: "Indique la raison (visible par le joueur).",
                                requireReply: true,
                                original: f.message ?? ""
                            )
                        }
                    } label: {
                        Text("✕ Refuser")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                } else {
                    Button {
                        Task { await reopenFeedback(f) }
                    } label: {
                        Text("Rouvrir")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }

                Button {
                    feedbackToDelete = f
                } label: {
                    Text("Suppr")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.error)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.error.opacity(0.45)))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: unread || f.isDone || f.isRejected ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var listBody: some View {
        if loading {
            Spacer()
            ProgressView("Ouverture du grimoire…").tint(Theme.accent)
            Spacer()
        } else if let error, players.isEmpty {
            Spacer()
            Text(error).foregroundStyle(Theme.error).padding()
            Spacer()
        } else if filtered.isEmpty {
            Spacer()
            Text("Aucun aventurier.").foregroundStyle(Theme.muted)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { p in
                        playerCard(p)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedUser = p.username }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
            }
        }
    }

    private func playerCard(_ p: RpgAdminPlayer) -> some View {
        let fill = min(1.0, max(0.0, (p.progressPct ?? 0) / 100.0))
        let master = p.beerMaster == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(master ? Color.yellow.opacity(0.15) : Theme.fieldBg)
                        .frame(width: 42, height: 42)
                    Circle()
                        .stroke(master ? Color.yellow.opacity(0.6) : Theme.accent.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                    Text(master ? "👑" : (p.classInfo?.icon ?? "🍺"))
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.username ?? "—")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(p.title ?? "Sans titre")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Text("Nv \(p.level ?? 1)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(colors: [Theme.accent, Color.orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
            }
            HStack(spacing: 4) {
                if p.isInvite == true { adminPill("invité", .invite) }
                if p.orphan == true { adminPill("orphelin", .off) }
                // Statut accès compact (détail = ON/OFF/Auto)
                if p.allowedOverride == true {
                    adminPill("RPG forcé", .on)
                } else if p.allowedOverride == false {
                    adminPill("RPG bloqué", .off)
                } else if p.allowed == false {
                    adminPill("RPG off", .off)
                } else {
                    adminPill("RPG", .on)
                }
                if p.hasProfile == false { adminPill("sans profil", .muted) }
                if p.suspicionFlagged == true || (p.suspicionScore ?? 0) >= 12 {
                    adminPill("⚠ \(p.suspicionScore ?? 0)", .off)
                }
                if p.quarantined == true {
                    adminPill("⛔ quarantaine", .off)
                }
                if p.dailySoftCapped == true {
                    let dx = p.dailyXpToday ?? p.dailyXpTotal ?? 0
                    let dc = p.dailySoftCap ?? 0
                    adminPill("cap \(dx)/\(dc)", .softcap)
                }
            }
            Text(metaLine(p))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if let dayLine = daySoftCapLine(p) {
                Text(dayLine)
                    .font(.system(size: 11, weight: p.dailySoftCapped == true ? .semibold : .regular))
                    .foregroundStyle(p.dailySoftCapped == true ? Color.yellow.opacity(0.9) : Theme.accent)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fieldBg)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accent, Color.yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * fill))
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: master
                    ? [Color(red: 0.22, green: 0.14, blue: 0.05), Theme.card]
                    : [Theme.card, Theme.card.opacity(0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(
                p.dailySoftCapped == true
                    ? Color.yellow.opacity(0.45)
                    : (master ? Color.yellow.opacity(0.35) : Theme.border)
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func metaLine(_ p: RpgAdminPlayer) -> String {
        var bits: [String] = []
        bits.append("\(p.xp ?? 0) XP")
        let cls = p.classInfo?.name ?? p.classKey
        if let c = cls, !c.isEmpty { bits.append(c) }
        bits.append("\(p.checkins ?? 0) check-ins")
        bits.append("\(p.badgeCount ?? 0) badges")
        if let s = p.streakDays, s > 0 { bits.append("🔥 \(s) j") }
        return bits.joined(separator: " · ")
    }

    /// XP du jour / soft-cap + check-ins RPG du jour (libellé clair, pas « 5 ck »).
    private func daySoftCapLine(_ p: RpgAdminPlayer) -> String? {
        let cap = p.dailySoftCap ?? 0
        guard cap > 0 else { return nil }
        let xp = p.dailyXpToday ?? p.dailyXpTotal ?? 0
        let ck = p.dailyCheckinsToday ?? p.dailyXpCount ?? 0
        let ckLabel = ck == 1 ? "1 check-in RPG" : "\(ck) check-ins RPG"
        if p.dailySoftCapped == true {
            return "⛔ \(xp)/\(cap) XP jour · \(ckLabel) · plafond"
        }
        if xp > 0 || ck > 0 {
            return "⚡ \(xp)/\(cap) XP jour · \(ckLabel)"
        }
        return nil
    }

    private enum PillKind { case on, off, invite, muted, softcap }

    private func adminPill(_ text: String, _ kind: PillKind) -> some View {
        let fg: Color
        let bg: Color
        let border: Color
        switch kind {
        case .on: fg = .green; bg = Color.green.opacity(0.12); border = Color.green.opacity(0.35)
        case .off: fg = Theme.error; bg = Theme.error.opacity(0.12); border = Theme.error.opacity(0.35)
        case .invite:
            fg = Color(red: 0.38, green: 0.65, blue: 0.98)
            bg = fg.opacity(0.12); border = fg.opacity(0.4)
        case .muted: fg = Theme.muted; bg = Theme.fieldBg; border = Theme.border
        case .softcap:
            fg = Color.yellow.opacity(0.95)
            bg = Color.yellow.opacity(0.12)
            border = Color.yellow.opacity(0.4)
        }
        return Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .overlay(Capsule().stroke(border))
            .clipShape(Capsule())
    }

    private func reload() async {
        loading = true
        error = nil
        do {
            let bundle = try await app.api.adminRpgPlayersBundle()
            players = bundle.players ?? []
            rpgFlags = bundle.flags
            // Badge feedback (léger, comme la webapp)
            if let stats = await app.api.adminFeedbackStats() {
                feedbackStats = stats
            }
            let unread = feedbackStats?.unread ?? 0
            let gameOn = rpgFlags?.enabled == true
            let lab = gameOn ? "Beerquest ON" : "Beerquest OFF"
            if unread > 0 {
                flagsLine = "\(lab) · \(players.count) joueur(s) · \(unread) feedback"
            } else {
                flagsLine = "\(lab) · \(players.count) joueur(s)"
            }
            // Si le jeu est coupé, atterrir sur Contrôle (première ouverture)
            if !didPickInitialTab {
                didPickInitialTab = true
                adminTab = gameOn ? .players : .control
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Erreur chargement"
        }
        loading = false
    }

    private func patchSetting(_ key: String, value: Bool) async {
        guard !settingsBusy else { return }
        settingsBusy = true
        defer { settingsBusy = false }
        do {
            // Allumer Beerquest = moteur + UI joueur (évite le piège « ON mais invisible »)
            var payload: [String: Any] = [key: value]
            if key == "enabled", value == true {
                payload["ui"] = true
            }
            rpgFlags = try await app.api.adminRpgPatchSettings(payload)
            let msg: String
            if key == "enabled" {
                msg = value ? "Beerquest allumé" : "Beerquest coupé"
            } else if key == "allow_invites" {
                msg = value ? "Invités inclus" : "Invités exclus"
            } else {
                msg = "Réglage enregistré"
            }
            app.showToast(msg, variant: .success, durationMs: 2400)
            // Rafraîchir le profil joueur local (HUD) si on allume/éteint
            Task { await app.refreshRpg() }
            await reload()
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Échec réglages",
                variant: .error,
                durationMs: 3200
            )
        }
    }

    private func loadFeedback() async {
        feedbackLoading = true
        feedbackError = nil
        do {
            let res = try await app.api.adminFeedbackList(
                limit: 80,
                unreadOnly: feedbackUnreadOnly,
                status: feedbackStatusFilter.isEmpty ? nil : feedbackStatusFilter
            )
            feedbackItems = res.items ?? []
            feedbackStats = res.stats
            let unread = res.stats?.unread ?? 0
            if unread > 0 {
                flagsLine = "\(players.count) aventurier(s) · \(unread) feedback non lu(s)"
            } else if !players.isEmpty {
                flagsLine = "\(players.count) aventurier(s) · grimoire admin"
            }
        } catch {
            feedbackError = (error as? LocalizedError)?.errorDescription ?? "Feedback indisponible"
        }
        feedbackLoading = false
    }

    private func toggleFeedbackRead(_ item: AdminFeedbackItem) async {
        guard let id = item.id else { return }
        feedbackBusyId = id
        defer { feedbackBusyId = nil }
        let next = item.adminRead != true
        do {
            try await app.api.adminFeedbackMarkRead(id: id, read: next)
            await loadFeedback()
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Erreur",
                variant: .error,
                durationMs: 3200
            )
        }
    }

    private func markAllFeedbackRead() async {
        do {
            try await app.api.adminFeedbackReadAll()
            await loadFeedback()
            app.showToast("Tout marqué lu", variant: .success, durationMs: 2400)
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Erreur",
                variant: .error,
                durationMs: 3200
            )
        }
    }

    private func resolveFeedback(id: Int, status: String, reply: String) async {
        feedbackBusyId = id
        defer { feedbackBusyId = nil }
        do {
            try await app.api.adminFeedbackResolve(id: id, status: status, reply: reply)
            await loadFeedback()
            app.showToast(
                status == "rejected" ? "Refusé — joueur notifié" : "Mis en place — joueur notifié",
                variant: .success,
                durationMs: 2800
            )
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Erreur",
                variant: .error,
                durationMs: 3200
            )
        }
    }

    private func reopenFeedback(_ item: AdminFeedbackItem) async {
        guard let id = item.id else { return }
        feedbackBusyId = id
        defer { feedbackBusyId = nil }
        do {
            try await app.api.adminFeedbackReopen(id: id)
            await loadFeedback()
            app.showToast("Feedback rouvert", variant: .success, durationMs: 2400)
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Erreur",
                variant: .error,
                durationMs: 3200
            )
        }
    }

    private func deleteFeedback(_ item: AdminFeedbackItem) async {
        feedbackToDelete = nil
        guard let id = item.id else { return }
        feedbackBusyId = id
        defer { feedbackBusyId = nil }
        do {
            try await app.api.adminFeedbackDelete(id: id)
            await loadFeedback()
            app.showToast("Feedback supprimé", variant: .success, durationMs: 2400)
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Suppression impossible",
                variant: .error,
                durationMs: 3200
            )
        }
    }
}

private struct UserKey: Identifiable {
    let id: String
}

private struct FeedbackResolveTarget: Identifiable {
    let id: Int
    let status: String
    let title: String
    let hint: String
    let requireReply: Bool
    let original: String
}

private struct FeedbackResolveSheet: View {
    let target: FeedbackResolveTarget
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var reply = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(target.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(target.hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if !target.original.isEmpty {
                    Text("« \(String(target.original.prefix(180)))\(target.original.count > 180 ? "…" : "") »")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .italic()
                }
                Text(target.requireReply ? "Raison (obligatoire)" : "Message pour le joueur (optionnel)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                TextEditor(text: $reply)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(Theme.fieldBg)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button("Annuler", action: onCancel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    Button {
                        onSubmit(reply.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Text("Envoyer")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(LinearGradient(colors: [Theme.accent, Color.orange], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(target.requireReply && reply.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .opacity(target.requireReply && reply.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.5 : 1)
                }
            }
            .padding(16)
            .background(Theme.bg)
        }
    }
}

// MARK: - Détail joueur

private struct RpgAdminPlayerDetailView: View {
    @EnvironmentObject private var app: AppModel
    let username: String
    let onClose: () -> Void

    @State private var detail: RpgAdminPlayerDetail?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?

    @State private var xpText = "0"
    @State private var levelText = "1"
    @State private var initialLevel = 1
    @State private var streakText = "0"
    @State private var titleText = ""
    @State private var classKey = "none"
    @State private var introSeen = true
    @State private var suspicionText = "0"
    @State private var confirmWipe = false
    @State private var badgeFilter = "all" // all | earned | locked

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.07, blue: 0.04), Theme.bg],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                Group {
                    if loading && detail == nil {
                        ProgressView("Lecture du parchemin…").tint(Theme.accent)
                    } else if let error, detail == nil {
                        Text(error).foregroundStyle(Theme.error).padding()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                if let err = error {
                                    Text(err).font(.caption).foregroundStyle(Theme.error)
                                }
                                profileHeader
                                editSection
                                actionsSection
                                badgesSection
                                questsSection
                                eventsSection
                            }
                            .padding(14)
                            .padding(.bottom, 40)
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("⚔ \(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", action: onClose)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { KeyboardDismiss.endEditing() }
                        .fontWeight(.semibold)
                }
            }
            .task { await load() }
            .confirmationDialog(
                "EFFACER tout le RPG de « \(username) » ?",
                isPresented: $confirmWipe,
                titleVisibility: .visible
            ) {
                Button("Effacer le RPG", role: .destructive) { Task { await wipe() } }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        let p = detail?.player
        let master = p?.beerMaster == true
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(master ? Color.yellow.opacity(0.18) : Theme.fieldBg)
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(
                            LinearGradient(colors: [Theme.accent, Color.yellow], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2.5
                        )
                        .frame(width: 64, height: 64)
                    Text(master ? "👑" : (p?.classInfo?.icon ?? "🍺"))
                        .font(.system(size: 28))
                    Text("\(p?.level ?? 1)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.card)
                        .clipShape(Capsule())
                        .offset(y: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(username)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text(p?.title ?? "Aventurier")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    HStack(spacing: 6) {
                        if p?.isInvite == true {
                            chip("invité", Color(red: 0.38, green: 0.65, blue: 0.98))
                        }
                        if p?.allowed != false {
                            chip("RPG OK", .green)
                        } else {
                            chip("bloqué", Theme.error)
                        }
                        if p?.allowedOverride == true {
                            chip("forcé ON", Theme.accent)
                        } else if p?.allowedOverride == false {
                            chip("forcé OFF", Theme.error)
                        }
                        if let cls = p?.classInfo?.name ?? p?.classKey, !cls.isEmpty {
                            chip(cls, Theme.muted)
                        }
                    }
                }
            }

            // Accès RPG compact (détail joueur)
            accessControlRow(p)

            // Stats RPG
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statBox("⚡", "\(p?.xp ?? 0)", "XP")
                statBox("🔥", "\(p?.streakDays ?? 0)", "Streak")
                statBox("🍺", "\(p?.checkins ?? 0)", "Check-ins")
                statBox("🏅", "\((detail?.badges ?? []).filter { $0.earned == true }.count)", "Badges")
                statBox("🎨", "\(detail?.atlas?.stylesCount ?? 0)", "Styles")
                statBox("⚠", "\(p?.suspicionScore ?? 0)", "Suspicion")
            }

            if p?.quarantined == true {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⛔ Quarantaine anti-triche active")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.error)
                    if let reason = p?.quarantineReason, !reason.isEmpty {
                        Text("Motif : \(reason)")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    if let at = p?.quarantineAt, !at.isEmpty {
                        Text("Depuis : \(at)")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.error.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.error.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            ProgressView(value: min(1, max(0, (p?.progressPct ?? 0) / 100.0)))
                .tint(Theme.accent)
            Text("\(Int(p?.progressPct ?? 0))% vers le niveau suivant")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: master
                    ? [Color(red: 0.25, green: 0.16, blue: 0.05), Theme.card]
                    : [Color(red: 0.12, green: 0.1, blue: 0.07), Theme.card],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.35), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(c)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(c.opacity(0.12))
            .overlay(Capsule().stroke(c.opacity(0.35)))
            .clipShape(Capsule())
    }

    private func accessControlRow(_ p: RpgAdminPlayer?) -> some View {
        let ov = p?.allowedOverride
        return HStack(spacing: 6) {
            Text("Accès")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.muted)
            accessSeg("ON", active: ov == true, tone: .on) {
                Task { await setUserAccess(true) }
            }
            accessSeg("OFF", active: ov == false, tone: .off) {
                Task { await setUserAccess(false) }
            }
            accessSeg("Auto", active: ov == nil, tone: .auto) {
                Task { await setUserAccess(nil) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.fieldBg.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private enum AccessTone { case on, off, auto }

    private func accessSeg(_ label: String, active: Bool, tone: AccessTone, action: @escaping () -> Void) -> some View {
        let bg: Color = {
            guard active else { return Theme.card }
            switch tone {
            case .on: return Color.green.opacity(0.85)
            case .off: return Theme.error.opacity(0.85)
            case .auto: return Theme.accent
            }
        }()
        let fg: Color = active ? Color(red: 0.07, green: 0.07, blue: 0.07) : Theme.muted
        return Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bg)
                .overlay(Capsule().stroke(Theme.border.opacity(active ? 0 : 1)))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func setUserAccess(_ allowed: Bool?) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.api.adminRpgSetUserAllowed(username: username, allowed: allowed)
            let lab: String
            switch allowed {
            case true?: lab = "RPG forcé ON"
            case false?: lab = "RPG forcé OFF"
            default: lab = "RPG = auto"
            }
            app.showToast("\(username) · \(lab)", variant: .success, durationMs: 2200)
            // recharger le détail
            if let d = try? await app.api.adminRpgPlayer(username) {
                applyDetail(d)
            }
        } catch {
            app.showToast(
                (error as? LocalizedError)?.errorDescription ?? "Échec accès user",
                variant: .error,
                durationMs: 3200
            )
        }
    }

    private func statBox(_ ico: String, _ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(ico).font(.system(size: 13))
            Text(v).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.fieldBg.opacity(0.7))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.8)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var editSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("📜 Éditer le profil")
            labeledField("Niveau (1–31)", text: $levelText, keyboard: .numberPad)
            Text("Changer le niveau place l’XP au début du palier. Ou édite seulement l’XP ci-dessous.")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            labeledField("XP (absolu)", text: $xpText, keyboard: .numberPad)
            labeledField("Streak (jours)", text: $streakText, keyboard: .numberPad)
            labeledField("Titre", text: $titleText, keyboard: .default)

            // Classe — liste cliquable (pas un menu invisible)
            VStack(alignment: .leading, spacing: 6) {
                Text("Classe équipée")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.muted)
                classPickerGrid
            }

            Toggle("Intro vue", isOn: $introSeen)
                .tint(Theme.accent)
                .foregroundStyle(Theme.text)
            labeledField("Suspicion (0–100)", text: $suspicionText, keyboard: .numberPad)

            if let last = detail?.player?.lastRpgCheckinAt {
                Text("Dernier RPG : \(last)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Button { Task { await save() } } label: {
                Text(busy ? "…" : "Enregistrer le parchemin")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [Theme.accent, .orange], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(busy)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var classPickerGrid: some View {
        let classes = detail?.classes ?? []
        return VStack(spacing: 6) {
            classPickRow(key: "none", label: "— aucune —", icon: "∅")
            ForEach(classes) { c in
                classPickRow(key: c.key ?? "", label: c.name ?? c.key ?? "—", icon: c.icon ?? "🍺")
            }
        }
    }

    private func classPickRow(key: String, label: String, icon: String) -> some View {
        let on = classKey == key
        return Button {
            classKey = key
        } label: {
            HStack {
                Text("\(icon) \(label)")
                    .font(.system(size: 13, weight: on ? .bold : .semibold))
                    .foregroundStyle(on ? Color(red: 0.07, green: 0.07, blue: 0.07) : Theme.text)
                Spacer()
                if on {
                    Text("✓").font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if on {
                    LinearGradient(colors: [Theme.accent, Color.orange.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                } else {
                    Theme.fieldBg
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(on ? Theme.accent : Theme.border, lineWidth: on ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("⚡ Actions rapides")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                actionBtn("+50 XP") { Task { await adjustXp(50) } }
                actionBtn("+200 XP") { Task { await adjustXp(200) } }
                actionBtn("−50 XP") { Task { await adjustXp(-50) } }
                actionBtn("Reset soft-cap") { Task { await resetDaily() } }
                actionBtn(detail?.player?.tutorialSeen == false ? "🎓 Reverra le tuto" : "🎓 Forcer tuto") { Task { await forceTutorial() } }
                    .disabled(detail?.player?.tutorialSeen == false)
                if detail?.player?.quarantined == true {
                    actionBtn("Lever quarantaine") { Task { await unquarantine() } }
                }
                Button { confirmWipe = true } label: {
                    Text("Effacer RPG")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.error.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(busy)
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var badgesSection: some View {
        let badges = detail?.badges ?? []
        let earned = badges.filter { $0.earned == true }
        let locked = badges.filter { $0.earned != true }
        let shown: [RpgBadge] = {
            switch badgeFilter {
            case "earned": return earned
            case "locked": return locked
            default: return badges
            }
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("🏅 Salle des trophées")
                Spacer()
                Text("\(earned.count)/\(badges.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }

            // Filtres
            HStack(spacing: 6) {
                filterChip("Tous", "all")
                filterChip("Obtenus", "earned")
                filterChip("À donner", "locked")
            }

            if shown.isEmpty {
                Text("Aucun badge dans ce filtre.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(shown) { b in
                        badgeTile(b)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func filterChip(_ title: String, _ key: String) -> some View {
        let on = badgeFilter == key
        return Button {
            badgeFilter = key
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? Color(red: 0.07, green: 0.07, blue: 0.07) : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(on ? Theme.accent : Theme.fieldBg)
                .overlay(Capsule().stroke(on ? Theme.accent : Theme.border))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func badgeTile(_ b: RpgBadge) -> some View {
        let earned = b.earned == true
        let rarity = (b.rarity ?? "common").lowercased()
        let rc: Color = {
            switch rarity {
            case "legendary": return .orange
            case "epic": return .purple
            case "rare": return Color(red: 0.38, green: 0.65, blue: 0.98)
            default: return Theme.muted
            }
        }()
        return VStack(spacing: 6) {
            Text(b.icon ?? "🏅").font(.title2)
            Text(b.name ?? "—")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 28)
            Text(rarityLabelFr(b.rarity))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(rc)
            Button {
                Task {
                    if earned {
                        await revokeBadge(b.key ?? "", name: b.name ?? b.key ?? "Badge")
                    } else {
                        await grantBadge(b.key ?? "", name: b.name ?? b.key ?? "Badge")
                    }
                }
            } label: {
                Text(earned ? "Retirer" : "Donner")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(earned ? Theme.error : Color(red: 0.07, green: 0.07, blue: 0.07))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(earned ? Theme.error.opacity(0.12) : Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(earned ? Theme.error.opacity(0.4) : Theme.accent))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(busy || (b.key ?? "").isEmpty)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: earned ? [rc.opacity(0.14), Theme.fieldBg] : [Theme.fieldBg, Theme.fieldBg],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(earned ? rc.opacity(0.5) : Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(earned ? 1 : 0.92)
    }

    @ViewBuilder
    private var questsSection: some View {
        let quests = detail?.quests ?? []
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("📜 Quêtes")
            if quests.isEmpty {
                Text("Aucune quête.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(quests.prefix(12)) { q in
                    let done = q.status == "done"
                    HStack {
                        Text(done ? "✅" : "⚔️")
                        Text("\(q.kind ?? "") · \(q.title ?? "—")")
                            .font(.caption)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        Text("\(q.progress ?? 0)/\(q.target ?? 0)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(done ? Color.green : Theme.muted)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var eventsSection: some View {
        let events = detail?.events ?? []
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("📖 Chronique")
            if events.isEmpty {
                Text("Aucun événement.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(events.prefix(10)) { ev in
                    Text("\(ev.kind ?? "?") · \(String((ev.createdAt ?? "").prefix(19)))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.text)
    }

    private func labeledField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.fieldBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.text)
        }
    }

    private func actionBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.fieldBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(busy)
    }

    private func applyDetail(_ d: RpgAdminPlayerDetail) {
        detail = d
        let p = d.player
        xpText = "\(p?.xp ?? 0)"
        let lvl = p?.level ?? 1
        levelText = "\(lvl)"
        initialLevel = lvl
        streakText = "\(p?.streakDays ?? 0)"
        titleText = p?.title ?? ""
        classKey = p?.classKey ?? "none"
        if classKey.isEmpty { classKey = "none" }
        introSeen = p?.introSeen != false
        suspicionText = "\(p?.suspicionScore ?? 0)"
    }

    private func load() async {
        loading = true
        error = nil
        do {
            applyDetail(try await app.api.adminRpgPlayer(username))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Erreur"
        }
        loading = false
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        var payload: [String: Any] = [
            "streak_days": Int(streakText) ?? 0,
            "title": titleText,
            "class": classKey,
            "intro_seen": introSeen,
            "suspicion_score": Int(suspicionText) ?? 0,
        ]
        let newLevel = max(1, min(31, Int(levelText) ?? initialLevel))
        if newLevel != initialLevel {
            // Priorité niveau → XP début de palier côté API
            payload["level"] = newLevel
        } else {
            payload["xp"] = max(0, Int(xpText) ?? 0)
        }
        do {
            applyDetail(try await app.api.adminRpgPatchPlayer(username, payload: payload))
            app.showToast("Parchemin enregistré", variant: .success, label: "Beerquest", durationMs: 2600)
        } catch {
            self.error = "Échec enregistrement"
            app.showToast("Échec enregistrement", variant: .error, durationMs: 2800)
        }
    }

    private func adjustXp(_ delta: Int) async {
        busy = true
        defer { busy = false }
        do {
            applyDetail(try await app.api.adminRpgAdjustXp(username: username, delta: delta))
            app.showToast("\(delta > 0 ? "+" : "")\(delta) XP", variant: .success, label: username, durationMs: 2400)
        } catch {
            app.showToast("Échec XP", variant: .error, durationMs: 2600)
        }
    }

    private func resetDaily() async {
        busy = true
        defer { busy = false }
        do {
            applyDetail(try await app.api.adminRpgResetDaily(username: username))
            app.showToast("Soft-cap du jour remis à 0", variant: .success, label: "Beerquest", durationMs: 2600)
        } catch {
            app.showToast("Échec reset", variant: .error, durationMs: 2600)
        }
    }

    private func forceTutorial() async {
        busy = true
        defer { busy = false }
        do {
            applyDetail(try await app.api.adminRpgPatchPlayer(username, payload: ["tutorial_seen": false]))
            app.showToast("\(username) reverra le tutoriel à sa prochaine connexion.", variant: .success, label: "Beerquest", durationMs: 2800)
        } catch {
            app.showToast("Échec tuto", variant: .error, durationMs: 2600)
        }
    }

    private func unquarantine() async {
        busy = true
        defer { busy = false }
        do {
            applyDetail(try await app.api.adminRpgUnquarantine(username))
            app.showToast("Quarantaine levée", variant: .success, label: "Beerquest", durationMs: 2400)
        } catch {
            app.showToast("Échec levée quarantaine", variant: .error, durationMs: 2600)
        }
    }

    private func grantBadge(_ key: String, name: String) async {
        guard !key.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            applyDetail(try await app.api.adminRpgGrantBadge(username: username, badgeKey: key))
            app.showToast("Badge accordé", variant: .success, detail: name, label: "🏅 Trophy", durationMs: 2800)
        } catch {
            app.showToast("Échec badge", variant: .error, durationMs: 2600)
        }
    }

    private func revokeBadge(_ key: String, name: String) async {
        guard !key.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            applyDetail(try await app.api.adminRpgRevokeBadge(username: username, badgeKey: key))
            app.showToast("Badge retiré", variant: .info, detail: name, label: "🏅 Trophy", durationMs: 2800)
        } catch {
            app.showToast("Échec retrait", variant: .error, durationMs: 2600)
        }
    }

    private func wipe() async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.adminRpgWipe(username: username)
            app.showToast("RPG effacé", variant: .success, label: username, durationMs: 3000)
            onClose()
        } catch {
            app.showToast("Échec wipe", variant: .error, durationMs: 2800)
        }
    }
}
