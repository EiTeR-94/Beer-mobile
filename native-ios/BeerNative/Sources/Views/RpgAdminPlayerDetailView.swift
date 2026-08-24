import SwiftUI

// MARK: - Détail joueur

struct RpgAdminPlayerDetailView: View {
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
