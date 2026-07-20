import SwiftUI

/// Admin Beerquest — parité webapp (liste + détail éditable + badges).
struct BeerquestAdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var players: [RpgAdminPlayer] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedUser: String?
    @State private var filter = ""
    @State private var flagsLine = "Profils RPG · alpha"

    private var filtered: [RpgAdminPlayer] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return players }
        return players.filter {
            ($0.username ?? "").lowercased().contains(q)
                || ($0.title ?? "").lowercased().contains(q)
                || ($0.classKey ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                searchBar
                listBody
            }
            .background(Theme.bg)
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
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("⚔ Beerquest")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(flagsLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button { Task { await reload() } } label: {
                Text("↻")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
            Button("Fermer") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text("🔍").font(.system(size: 13))
            TextField("nom, invite_…", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.fieldBg)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var listBody: some View {
        if loading {
            Spacer()
            ProgressView("Chargement…").tint(Theme.accent)
            Spacer()
        } else if let error, players.isEmpty {
            Spacer()
            Text(error).foregroundStyle(Theme.error).padding()
            Spacer()
        } else if filtered.isEmpty {
            Spacer()
            Text("Aucun joueur.").foregroundStyle(Theme.muted)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { p in
                        Button { selectedUser = p.username } label: {
                            playerCard(p)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
            }
        }
    }

    private func playerCard(_ p: RpgAdminPlayer) -> some View {
        let fill = min(1.0, max(0.0, (p.progressPct ?? 0) / 100.0))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(p.username ?? "—")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 4) {
                    if p.isInvite == true { adminPill("invité", .invite) }
                    if p.orphan == true { adminPill("orphelin", .off) }
                    if p.allowed == false { adminPill("RPG bloqué", .off) }
                    else { adminPill("RPG OK", .on) }
                    if p.hasProfile == false { adminPill("sans profil", .muted) }
                    if p.suspicionFlagged == true || (p.suspicionScore ?? 0) >= 12 {
                        adminPill("⚠ susp \(p.suspicionScore ?? 0)", .off)
                    }
                }
            }
            Text(metaLine(p))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func metaLine(_ p: RpgAdminPlayer) -> String {
        var bits: [String] = ["Lv \(p.level ?? 1)"]
        if let t = p.title, !t.isEmpty { bits.append(t) }
        let cls = p.classInfo?.name ?? p.classKey
        if let c = cls, !c.isEmpty { bits.append(c) }
        bits.append("\(p.xp ?? 0) XP")
        bits.append("\(p.checkins ?? 0) check-in(s)")
        bits.append("\(p.badgeCount ?? 0) badge(s)")
        if let s = p.streakDays, s > 0 { bits.append("🔥 \(s) j") }
        return bits.joined(separator: " · ")
    }

    private enum PillKind { case on, off, invite, muted }

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
            players = try await app.api.adminRpgPlayers()
            flagsLine = "\(players.count) joueur(s) · profils RPG"
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Erreur chargement"
        }
        loading = false
    }
}

private struct UserKey: Identifiable {
    let id: String
}

// MARK: - Détail joueur (édition + badges)

private struct RpgAdminPlayerDetailView: View {
    @EnvironmentObject private var app: AppModel
    let username: String
    let onClose: () -> Void

    @State private var detail: RpgAdminPlayerDetail?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?

    // editable fields
    @State private var xpText = "0"
    @State private var streakText = "0"
    @State private var titleText = ""
    @State private var classKey = "none"
    @State private var introSeen = true
    @State private var suspicionText = "0"
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && detail == nil {
                    ProgressView("Chargement \(username)…").tint(Theme.accent)
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
                        .padding(16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle(username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", action: onClose)
                }
            }
            .task { await load() }
            .confirmationDialog(
                "EFFACER tout le RPG de « \(username) » ?\n(profil, badges, quêtes — pas les check-ins)",
                isPresented: $confirmWipe,
                titleVisibility: .visible
            ) {
                Button("Effacer le RPG", role: .destructive) {
                    Task { await wipe() }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        let p = detail?.player
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(username).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                if p?.isInvite == true {
                    Text("invité").font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                }
                if p?.allowed != false {
                    Text("RPG OK").font(.caption.weight(.bold)).foregroundStyle(.green)
                } else {
                    Text("RPG bloqué").font(.caption.weight(.bold)).foregroundStyle(Theme.error)
                }
            }
            let chips = [
                "Lv \(p?.level ?? 1)",
                "\(p?.xp ?? 0) XP",
                "\(p?.checkins ?? 0) check-ins",
                "🔥 \(p?.streakDays ?? 0) j",
                "daily \(p?.dailyXpTotal ?? 0) XP",
                "atlas \(detail?.atlas?.stylesCount ?? 0) styles",
                "susp \(p?.suspicionScore ?? 0)",
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                ForEach(chips, id: \.self) { s in
                    Text(s)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            if let aff = detail?.classAffinity, !aff.isEmpty {
                Text("Affinité : " + aff.map { "\($0.key) \($0.value)%" }.sorted().joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            ProgressView(value: min(1, max(0, (p?.progressPct ?? 0) / 100.0)))
                .tint(Theme.accent)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var editSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Éditer le profil")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            field("XP (absolu — fixe le niveau)", text: $xpText, keyboard: .numberPad)
            field("Streak (jours)", text: $streakText, keyboard: .numberPad)
            field("Titre", text: $titleText, keyboard: .default)
            VStack(alignment: .leading, spacing: 4) {
                Text("Classe").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                Picker("Classe", selection: $classKey) {
                    Text("— aucune —").tag("none")
                    ForEach(detail?.classes ?? []) { c in
                        Text("\(c.icon ?? "🍺") \(c.name ?? c.key ?? "")").tag(c.key ?? "")
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            Toggle("Intro vue", isOn: $introSeen)
                .tint(Theme.accent)
                .foregroundStyle(Theme.text)
            field("Suspicion (0–100)", text: $suspicionText, keyboard: .numberPad)
            if let last = detail?.player?.lastRpgCheckinAt {
                Text("Dernier RPG : \(last)")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Button {
                Task { await save() }
            } label: {
                Text(busy ? "…" : "Enregistrer")
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

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions rapides")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                actionBtn("+50 XP") { Task { await adjustXp(50) } }
                actionBtn("+200 XP") { Task { await adjustXp(200) } }
                actionBtn("−50 XP") { Task { await adjustXp(-50) } }
                actionBtn("Reset soft-cap jour") { Task { await resetDaily() } }
                actionBtn("Clear suspicion") { Task { await clearSuspicion() } }
                Button {
                    confirmWipe = true
                } label: {
                    Text("Effacer tout le RPG")
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Badges")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            if badges.isEmpty {
                Text("Aucun badge catalogue.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(badges) { b in
                    HStack(spacing: 8) {
                        Text(b.icon ?? "🏅")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.name ?? b.key ?? "—")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Text(rarityLabelFr(b.rarity))
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if b.earned == true {
                            Button("Retirer") {
                                Task { await revokeBadge(b.key ?? "") }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.error)
                            .disabled(busy)
                        } else {
                            Button("Donner") {
                                Task { await grantBadge(b.key ?? "") }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .disabled(busy)
                        }
                    }
                    .padding(8)
                    .background(Theme.fieldBg.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var questsSection: some View {
        let quests = detail?.quests ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("Quêtes")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            if quests.isEmpty {
                Text("Aucune quête.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(quests.prefix(20)) { q in
                    Text("[\(q.status ?? "?")] \(q.kind ?? "") · \(q.title ?? "—") · \(q.progress ?? 0)/\(q.target ?? 0) · +\(q.rewardXp ?? 0) XP")
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

    @ViewBuilder
    private var eventsSection: some View {
        let events = detail?.events ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text("Événements récents")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            if events.isEmpty {
                Text("Aucun événement.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(events.prefix(15)) { ev in
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

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.fieldBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
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
            let d = try await app.api.adminRpgPlayer(username)
            applyDetail(d)
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
            "xp": Int(xpText) ?? 0,
            "streak_days": Int(streakText) ?? 0,
            "title": titleText,
            "class": classKey,
            "intro_seen": introSeen,
            "suspicion_score": Int(suspicionText) ?? 0,
        ]
        do {
            let d = try await app.api.adminRpgPatchPlayer(username, payload: payload)
            applyDetail(d)
            app.showToast("Profil mis à jour — \(username)", variant: .success, label: "Beerquest")
        } catch {
            self.error = "Échec enregistrement"
            app.showToast("Échec enregistrement", variant: .error)
        }
    }

    private func adjustXp(_ delta: Int) async {
        busy = true
        defer { busy = false }
        do {
            let d = try await app.api.adminRpgAdjustXp(username: username, delta: delta)
            applyDetail(d)
            app.showToast("XP \(delta > 0 ? "+" : "")\(delta) → \(username)", variant: .success, label: "Beerquest")
        } catch {
            app.showToast("Échec XP", variant: .error)
        }
    }

    private func resetDaily() async {
        busy = true
        defer { busy = false }
        do {
            let d = try await app.api.adminRpgResetDaily(username: username)
            applyDetail(d)
            app.showToast("Soft-cap journalier réinitialisé", variant: .success, label: "Beerquest")
        } catch {
            app.showToast("Échec reset", variant: .error)
        }
    }

    private func clearSuspicion() async {
        busy = true
        defer { busy = false }
        do {
            let d = try await app.api.adminRpgPatchPlayer(username, payload: ["suspicion_score": 0])
            applyDetail(d)
            app.showToast("Suspicion effacée", variant: .success, label: "Beerquest")
        } catch {
            app.showToast("Échec", variant: .error)
        }
    }

    private func grantBadge(_ key: String) async {
        guard !key.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let d = try await app.api.adminRpgGrantBadge(username: username, badgeKey: key)
            applyDetail(d)
            app.showToast("Badge accordé", variant: .success, label: "Beerquest")
        } catch {
            app.showToast("Échec badge", variant: .error)
        }
    }

    private func revokeBadge(_ key: String) async {
        guard !key.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let d = try await app.api.adminRpgRevokeBadge(username: username, badgeKey: key)
            applyDetail(d)
            app.showToast("Badge retiré", variant: .success, label: "Beerquest")
        } catch {
            app.showToast("Échec retrait", variant: .error)
        }
    }

    private func wipe() async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.adminRpgWipe(username: username)
            app.showToast("RPG effacé — \(username)", variant: .success, label: "Beerquest")
            onClose()
        } catch {
            app.showToast("Échec wipe", variant: .error)
        }
    }
}
