import SwiftUI

// MARK: - Grimoire (parité webapp beerquest.js / beerquest.css)

struct GrimoireSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var detailBadge: RpgBadge?

    private let tabs: [(ico: String, lbl: String)] = [
        ("🏠", "Accueil"),
        ("📜", "Quêtes"),
        ("🏅", "Badges"),
        ("🗺️", "Atlas"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // En-tête type web : Grimoire + sous-titre taverne
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grimoire")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("Beerquest · taverne personnelle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // Onglets type .bq-tabs (icône + label, grille 4)
                HStack(spacing: 6) {
                    ForEach(0..<tabs.count, id: \.self) { i in
                        BqTabButton(
                            ico: tabs[i].ico,
                            label: tabs[i].lbl,
                            selected: tab == i
                        ) { tab = i }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                Group {
                    if let st = app.rpgState, st.active, let p = st.profile {
                        switch tab {
                        case 0: homeTab(st, p)
                        case 1: questsTab(st)
                        case 2: badgesTab(st)
                        default: atlasTab(st, p)
                        }
                    } else {
                        Text(emptyMessage)
                            .foregroundStyle(Theme.muted)
                            .padding()
                        Spacer()
                    }
                }
            }
            .background(Theme.bg)
            .navigationBarHidden(true)
            .task { await app.refreshRpg() }
            .sheet(item: $detailBadge) { b in
                RpgBadgeDetailView(badge: b) { detailBadge = nil }
                    .preferredColorScheme(.dark)
            }
        }
    }

    private var emptyMessage: String {
        if app.rpgState?.enabled == false {
            return "Beerquest est désactivé sur le serveur."
        }
        return "Beerquest n’est pas disponible pour ce compte."
    }

    // MARK: - Accueil

    @ViewBuilder
    private func homeTab(_ st: RpgState, _ p: RpgProfile) -> some View {
        let master = p.beerMaster == true
        let nActive = st.quests?.active?.count ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if master {
                    masterCard(p)
                }
                // Fiche d’aventurier (card unique comme web)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fiche d’aventurier")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                        .tracking(0.6)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.fieldBg)
                                .frame(width: 64, height: 64)
                            Circle()
                                .stroke(master ? Color.yellow : Theme.accent, lineWidth: 2.5)
                                .frame(width: 64, height: 64)
                            Text(p.displayIcon).font(.system(size: 28))
                            Text("\(p.level ?? 1)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.card.opacity(0.95))
                                .clipShape(Capsule())
                                .offset(y: 26)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title ?? "Aventurier")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.text)
                            if master {
                                Text("Profil unique · Beer Master")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.yellow)
                            } else {
                                let cn = p.classInfo?.name ?? p.classKey ?? "Aventurier"
                                let ci = p.classInfo?.icon ?? "🍺"
                                Text("Classe · \(ci) \(cn)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                            if let band = p.titleBand?.name, !master {
                                Text(band)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.12))
                                    .clipShape(Capsule())
                            } else if master {
                                Text("Prestige")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.yellow)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    xpHeroBar(p)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        statTile("🔥", "\(p.streakDays ?? 0)", "Streak")
                        statTile("⚡", "\(p.dailyXp ?? 0)/\(p.dailySoftCap ?? 100)", "XP du jour")
                        statTile("🍺", "\(st.atlas?.totalCheckins ?? 0)", "Check-ins")
                        if master {
                            statTile("👑", "Unique", "Prestige")
                        } else {
                            statTile("📜", "\(nActive)", "Quêtes")
                        }
                    }
                }
                .padding(14)
                .background(cardBg(master: master))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(master ? Color.yellow.opacity(0.4) : Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Quêtes en cours
                sectionCard(title: "Quêtes en cours", ico: "📜", count: nActive > 0 ? nActive : nil) {
                    let active = Array((st.quests?.active ?? []).prefix(3))
                    if active.isEmpty {
                        Text("Aucune quête active — le tavernier en prépare pour demain.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(active) { QuestCardView(q: $0) }
                    }
                }

                // Prochains badges
                if let next = st.nextBadges, !next.isEmpty {
                    sectionCard(title: "Prochains badges", ico: "🏅", count: next.count) {
                        ForEach(next) { b in
                            Button { detailBadge = b } label: {
                                NextBadgeRow(b: b)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Le tavernier
                sectionCard(title: "Le tavernier", ico: "🗣️", count: nil) {
                    Text(st.phrase ?? "…")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Quêtes (Missions de la taverne)

    @ViewBuilder
    private func questsTab(_ st: RpgState) -> some View {
        let active = st.quests?.active ?? []
        let doneToday = st.quests?.doneToday ?? []
        let doneWeekly = st.quests?.doneWeekly ?? []
        let dailies = active.filter { $0.kind == "daily" } + doneToday
        let weeklies = active.filter { $0.kind == "weekly" } + doneWeekly
        let story = active.filter { $0.kind == "story" }
        let nOpen = active.filter { ($0.status ?? "") != "done" }.count
        let nDone = doneToday.count + doneWeekly.count
        let nTotal = active.count + doneToday.count + doneWeekly.count

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                tabHero(
                    kicker: "Tableau des quêtes",
                    title: "📜 Missions de la taverne",
                    blurb: "Accomplis des objectifs pour gagner de l’XP. Les journalières se renouvellent chaque jour."
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        statTile("⚔️", "\(nOpen)", "Actives")
                        statTile("✅", "\(nDone)", "Finies")
                        statTile("✨", "\(nTotal)", "Total")
                    }
                }

                sectionCard(title: "Journalières", ico: "☀️", count: dailies.isEmpty ? nil : dailies.count) {
                    if dailies.isEmpty {
                        Text("Pas de quête du jour — reviens demain.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(dailies) { QuestCardView(q: $0) }
                    }
                }
                sectionCard(title: "Hebdomadaires", ico: "📅", count: weeklies.isEmpty ? nil : weeklies.count) {
                    if weeklies.isEmpty {
                        Text("Aucune quête hebdo pour l’instant.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(weeklies) { QuestCardView(q: $0) }
                    }
                }
                sectionCard(title: "Histoire", ico: "📖", count: story.isEmpty ? nil : story.count) {
                    if story.isEmpty {
                        Text("Chapitres à venir… le tavernier écrit encore.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(story) { QuestCardView(q: $0) }
                    }
                }
            }
            .padding(12)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private func badgesTab(_ st: RpgState) -> some View {
        let badges = st.badges ?? []
        let earnedList = badges.filter { $0.earned == true }
            .sorted { rarityOrder($0.rarity) > rarityOrder($1.rarity) }
        let locked = badges.filter { $0.earned != true }
        let inProgress = locked
            .filter { ($0.progress ?? 0) > 0 }
            .sorted {
                let ta = max(1, $0.target ?? 1)
                let tb = max(1, $1.target ?? 1)
                return (Double($0.progress ?? 0) / Double(ta)) > (Double($1.progress ?? 0) / Double(tb))
            }
        let untouched = locked.filter { ($0.progress ?? 0) <= 0 }
        let common = untouched.filter { ($0.rarity ?? "common").lowercased() == "common" }
        let rare = untouched.filter { ($0.rarity ?? "").lowercased() == "rare" }
        let epic = untouched.filter { ($0.rarity ?? "").lowercased() == "epic" }
        let legendary = untouched.filter { ($0.rarity ?? "").lowercased() == "legendary" }
        let nEarned = earnedList.count
        let nTotal = badges.count
        let pctAll = nTotal > 0 ? (nEarned * 100 / nTotal) : 0

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                tabHero(
                    kicker: "Salle des trophées",
                    title: "🏅 Collection de badges",
                    blurb: "Chaque badge a un objectif clair. Touche une tuile pour voir comment l’obtenir, ta progression et l’ambiance."
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        statTile("🏆", "\(nEarned)", "Obtenus")
                        statTile("🔒", "\(locked.count)", "À faire")
                        statTile("📊", "\(pctAll)%", "Complétion")
                    }
                    ProgressView(value: Double(pctAll) / 100.0)
                        .tint(Color.purple)
                    HStack {
                        Text("\(nEarned) / \(nTotal) badges")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(max(0, nTotal - nEarned)) restants")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 12) {
                        legendDot(Color.gray, "Commun")
                        legendDot(Color(red: 0.38, green: 0.65, blue: 0.98), "Rare")
                        legendDot(Color.purple, "Épique")
                        legendDot(Color.orange, "Légendaire")
                    }
                }

                badgeGroup("En cours", "⚔️", inProgress)
                badgeGroup("Commun", "⚪", common)
                badgeGroup("Rare", "🔵", rare)
                badgeGroup("Épique", "🟣", epic)
                badgeGroup("Légendaire", "🟡", legendary)
                badgeGroup("Obtenus", "✅", earnedList)
            }
            .padding(12)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Atlas

    @ViewBuilder
    private func atlasTab(_ st: RpgState, _ p: RpgProfile) -> some View {
        let master = p.beerMaster == true
        let aff = st.classAffinity ?? [:]
        let classes = st.classes ?? []
        let equippedKey = p.classKey
        let recKey = bestAffinityKey(aff, classes)
        let equipped = classes.first { $0.key == equippedKey }
        let others = classes.filter { $0.key != equippedKey }
        let styles = st.atlas?.styles ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                tabHero(
                    kicker: "Carte du royaume",
                    title: "🗺️ Atlas du dégustateur",
                    blurb: "Ta collection, tes territoires de goût, et la classe qui te définit à la taverne.",
                    master: master
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        statTile("🎨", "\(st.atlas?.stylesCount ?? 0)", "Styles")
                        statTile("🌿", "\(st.atlas?.hopsCount ?? 0)", "Houblons")
                        statTile("🏭", "\(st.atlas?.breweriesCount ?? 0)", "Brasseries")
                        statTile("📷", "\(st.atlas?.photos ?? 0)", "Photos")
                    }
                    HStack(spacing: 6) {
                        if let eq = equipped {
                            Text("Équipée · \((eq.icon ?? "") + " " + (eq.name ?? eq.key ?? "")).trimmingCharacters(in: .whitespaces)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        if let rk = recKey, rk != equippedKey,
                           let rec = classes.first(where: { $0.key == rk }) {
                            Text("Plus jouée · \((rec.icon ?? "") + " " + (rec.name ?? rk)).trimmingCharacters(in: .whitespaces)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Styles découverts
                sectionCard(
                    title: "Styles découverts",
                    ico: "🍺",
                    count: st.atlas?.stylesCount
                ) {
                    if styles.isEmpty {
                        Text("Aucun style noté pour l’instant — goûte et logue !")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        FlowStyleChips(styles: styles)
                    }
                }

                // Classes
                sectionCard(title: "Classes", ico: "⚔️", count: equipped != nil ? 1 : nil) {
                    Text("Une seule spécialité à la fois. Si la bière colle : +2 XP, parfois un bonus, et de l’habitude (le % à droite). Max 12 XP de classe par bière.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if let eq = equipped {
                        Text("Classe équipée")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.yellow.opacity(0.95))
                            .tracking(0.4)
                            .padding(.top, 4)
                        ClassCardView(
                            c: eq,
                            aff: aff[eq.key ?? ""] ?? 0,
                            equipped: true,
                            recommended: eq.key == recKey
                        ) {}
                    }

                    if !others.isEmpty {
                        Text("Autres classes · toucher pour équiper")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                            .tracking(0.4)
                            .padding(.top, 6)
                        ForEach(others) { c in
                            let key = c.key ?? ""
                            ClassCardView(
                                c: c,
                                aff: aff[key] ?? 0,
                                equipped: false,
                                recommended: key == recKey
                            ) {
                                Task { await app.equipRpgClass(key) }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Shared UI bits

    private func bestAffinityKey(_ aff: [String: Int], _ classes: [RpgClassInfo]) -> String? {
        var best: String?
        var bestVal = -1
        for c in classes {
            guard let k = c.key else { continue }
            let v = aff[k] ?? 0
            if v > bestVal {
                bestVal = v
                best = k
            }
        }
        return best
    }

    private func rarityOrder(_ r: String?) -> Int {
        switch (r ?? "common").lowercased() {
        case "legendary": return 3
        case "epic": return 2
        case "rare": return 1
        default: return 0
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func badgeGroup(_ title: String, _ ico: String, _ list: [RpgBadge]) -> some View {
        if !list.isEmpty {
            sectionCard(title: title, ico: ico, count: list.count) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(list) { b in
                        Button { detailBadge = b } label: {
                            BadgeTileView(b: b)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func cardBg(master: Bool = false) -> some View {
        LinearGradient(
            colors: master
                ? [Color(red: 0.28, green: 0.18, blue: 0.05), Theme.card]
                : [Theme.card, Theme.card.opacity(0.98)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func tabHero<Content: View>(
        kicker: String,
        title: String,
        blurb: String,
        master: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(master ? Color.yellow.opacity(0.9) : Theme.muted)
                .tracking(0.8)
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(blurb)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg(master: master))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(master ? Color.yellow.opacity(0.4) : Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        ico: String,
        count: Int?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(ico) \(title)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.fieldBg)
                        .clipShape(Capsule())
                }
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statTile(_ ico: String, _ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(ico).font(.system(size: 14))
            Text(v)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.fieldBg.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func masterCard(_ p: RpgProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("👑").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.prestige?.ribbon ?? "BEER MASTER")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.yellow)
                    Text(p.title ?? "Beer Master")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text(p.prestige?.tagline ?? "Couronne de la taverne")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            if let blurb = p.prestige?.blurb, !blurb.isEmpty {
                Text(blurb).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.22, green: 0.14, blue: 0.04).opacity(0.95))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func xpHeroBar(_ p: RpgProfile) -> some View {
        let into = p.xpIntoLevel
        let span: Int? = {
            if let s = p.xpLevelStart, let n = p.xpLevelNext { return max(1, n - s) }
            return nil
        }()
        let pct = min(1, max(0, (p.progressPct ?? 0) / 100.0))
        let mid: String = {
            if let into, let span { return "\(into) / \(span) XP" }
            return "\(p.xp ?? 0) XP"
        }()
        VStack(spacing: 6) {
            HStack {
                Text("Nv \(p.level ?? 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.fieldBg)
                    .clipShape(Capsule())
                Spacer()
                Text(mid)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(p.xpToNext.map { "encore \($0)" } ?? "max")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fieldBg)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * pct))
                }
            }
            .frame(height: 10)
            Text("\(Int((p.progressPct ?? 0).rounded()))% vers le prochain niveau")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Tab button (parité .bq-tab)

private struct BqTabButton: View {
    let ico: String
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(ico).font(.system(size: 16))
                Text(label)
                    .font(.system(size: 11, weight: selected ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color(red: 0.07, green: 0.07, blue: 0.07) : Theme.muted)
            .background(
                Group {
                    if selected {
                        LinearGradient(
                            colors: [Theme.accent, Color(red: 0.85, green: 0.55, blue: 0.1)],
                            startPoint: .top, endPoint: .bottom
                        )
                    } else {
                        Theme.card
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Theme.accent : Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: selected ? Theme.accent.opacity(0.35) : .clear, radius: 6, y: 0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quest card (parité web)

struct QuestCardView: View {
    let q: RpgQuest

    private var kindMeta: (label: String, ico: String, color: Color) {
        switch (q.kind ?? "").lowercased() {
        case "daily": return ("Journalière", "☀️", Color(red: 0.38, green: 0.65, blue: 0.98))
        case "weekly": return ("Hebdo", "📅", Color.purple)
        case "story": return ("Histoire", "📖", Color.orange)
        default: return ("Quête", "📜", Color(red: 0.38, green: 0.65, blue: 0.98))
        }
    }

    var body: some View {
        let done = q.status == "done"
        let tgt = max(1, q.target ?? 1)
        let prog = q.progress ?? 0
        let pct = min(1, Double(prog) / Double(tgt))
        let meta = kindMeta
        let statusLabel = done ? "Terminée" : (pct > 0 ? "En cours" : "À faire")
        let border = done ? Color.green : meta.color

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(meta.ico) \(meta.label)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(meta.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(meta.color.opacity(0.12))
                        .overlay(Capsule().stroke(meta.color.opacity(0.35)))
                        .clipShape(Capsule())
                    Text(q.title ?? "—")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.text)
                }
                Spacer(minLength: 8)
                Text("✨ +\(q.rewardXp ?? 0) XP")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.yellow)
            }
            if let d = q.description, !d.isEmpty {
                Text(d).font(.caption).foregroundStyle(Theme.muted)
            }
            HStack {
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(done ? Color.green : meta.color)
                Spacer()
                Text("\(prog)/\(tgt) · \(Int(pct * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            ProgressView(value: pct)
                .tint(done ? .green : meta.color)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [border.opacity(0.08), Theme.card],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(border.opacity(0.7), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(border)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 4)
    }
}

// MARK: - Next badge row (accueil)

private struct NextBadgeRow: View {
    let b: RpgBadge
    var body: some View {
        let tgt = max(1, b.target ?? 1)
        let prog = b.progress ?? 0
        let pct = min(1, Double(prog) / Double(tgt))
        HStack(alignment: .top, spacing: 10) {
            Text(b.icon ?? "🏅").font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(b.name ?? "Badge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(rarityLabelFr(b.rarity))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(rarityColor(b.rarity))
                }
                if let h = b.hint?.replacingOccurrences(of: "Objectif : ", with: ""), !h.isEmpty {
                    Text(h).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
                HStack {
                    Text("\(prog) / \(tgt)" + (b.remaining.map { " · encore \($0)" } ?? ""))
                        .font(.caption2).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(Int(pct * 100))%").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
                }
                ProgressView(value: pct).tint(Color.purple)
            }
        }
        .padding(10)
        .background(Theme.fieldBg.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func rarityColor(_ r: String?) -> Color {
        switch (r ?? "").lowercased() {
        case "legendary": return .orange
        case "epic": return .purple
        case "rare": return Color(red: 0.38, green: 0.65, blue: 0.98)
        default: return Theme.muted
        }
    }
}

// MARK: - Class card (Atlas)

private struct ClassCardView: View {
    let c: RpgClassInfo
    let aff: Int
    let equipped: Bool
    let recommended: Bool
    let onEquip: () -> Void

    private var when: String { c.whenText ?? "Quand la bière colle à la classe" }
    private var special: String {
        (c.special ?? "Bonus si condition remplie").replacingOccurrences(of: "**", with: "")
    }
    private var habit: String {
        if aff >= 70 { return "+3 XP d’habitude" }
        if aff >= 50 { return "+2 XP d’habitude" }
        if aff >= 25 { return "+1 XP d’habitude" }
        return "pas encore d’habitude (+0)"
    }

    var body: some View {
        Button(action: onEquip) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(c.icon ?? "🍺") \(c.name ?? c.key ?? "—")")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    if let b = c.blurb, !b.isEmpty {
                        Text(b).font(.caption).foregroundStyle(Theme.muted)
                    }
                    (Text("QUAND ").font(.system(size: 9, weight: .heavy)).foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                     + Text(when + " → ").font(.system(size: 11)).foregroundColor(Theme.muted)
                     + Text("+2 XP").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text))
                    (Text("EN PLUS ").font(.system(size: 9, weight: .heavy)).foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                     + Text(special).font(.system(size: 11)).foregroundColor(Theme.muted))
                    Text((equipped ? "Active · " : "Si tu l’équipes · ") + habit + " si la bière colle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(equipped ? Color.green : Theme.muted)
                    pill
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Text("HABITUDE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .tracking(0.4)
                    Text("\(aff)%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(habit)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(width: 72)
                .padding(6)
                .background(Theme.fieldBg.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [4])))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(12)
            .background(
                equipped
                    ? LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.card], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Theme.card, Theme.card], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        equipped ? Theme.accent
                            : (recommended ? Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.55) : Theme.border),
                        lineWidth: equipped ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(equipped ? 1 : 0.88)
        }
        .buttonStyle(.plain)
        .disabled(equipped)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var pill: some View {
        if equipped {
            Text("ÉQUIPÉE")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.accent)
                .clipShape(Capsule())
        } else if recommended {
            Text("Celle que tu joues le plus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.15))
                .overlay(Capsule().stroke(Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.4)))
                .clipShape(Capsule())
        } else {
            Text("Toucher pour équiper")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3])))
        }
    }
}

// MARK: - Style chips

struct FlowStyleChips: View {
    let styles: [String]
    private var shown: [String] { Array(styles.prefix(24)) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
            ForEach(shown, id: \.self) { s in
                Text(s)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.fieldBg)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if styles.count > 24 {
                Text("+\(styles.count - 24)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Badge tiles (inchangé structure, polish léger)

struct BadgeProgressView: View {
    let b: RpgBadge
    var body: some View {
        NextBadgeRow(b: b)
    }
}

struct BadgeTileView: View {
    let b: RpgBadge
    var body: some View {
        let earned = b.earned == true
        let tgt = max(1, b.target ?? 1)
        let prog = b.progress ?? 0
        let pct = min(1, Double(prog) / Double(tgt))
        let rarity = (b.rarity ?? "common").lowercased()
        let rarityColor: Color = {
            switch rarity {
            case "legendary": return .orange
            case "epic": return .purple
            case "rare": return Color(red: 0.38, green: 0.65, blue: 0.98)
            default: return Theme.muted
            }
        }()
        let border: Color = {
            if earned { return rarityColor }
            if prog > 0 { return Color.yellow.opacity(0.55) }
            return Theme.border
        }()
        VStack(spacing: 4) {
            Text(b.icon ?? "🏅").font(.title2)
            Text(b.name ?? "—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(rarityLabelFr(b.rarity))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(rarityColor)
            Text(earned ? "✓ Obtenu" : "\(prog)/\(tgt) · \(Int(pct * 100))%")
                .font(.system(size: 10, weight: earned ? .bold : .semibold))
                .foregroundStyle(earned ? Color.green : Theme.muted)
                .lineLimit(1)
            if !earned {
                ProgressView(value: pct)
                    .tint(prog > 0 ? Color.yellow : rarityColor)
                if let h = b.hint?
                    .replacingOccurrences(of: "Objectif : ", with: "")
                    .replacingOccurrences(of: "Objectif:", with: ""),
                   !h.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(h)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: earned
                    ? [rarityColor.opacity(0.18), Theme.card]
                    : (prog > 0 ? [Color.yellow.opacity(0.08), Theme.card] : [Theme.card, Theme.card]),
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// HUD card (accueil app) — conservé pour MainView
struct BqHudCard: View {
    let profile: RpgProfile
    var onTap: () -> Void

    private struct FrameStyle {
        let band: String
        let border: Color
        let borderWidth: CGFloat
        let outer: Color?
        let bgTop: Color
        let accent: Color
        let seal: Color
    }

    private var frame: FrameStyle {
        if profile.beerMaster == true {
            return FrameStyle(
                band: profile.prestige?.ribbon ?? "Beer Master",
                border: Color.yellow.opacity(0.75),
                borderWidth: 2,
                outer: Color.yellow.opacity(0.3),
                bgTop: Color(red: 0.47, green: 0.21, blue: 0.06).opacity(0.45),
                accent: .yellow,
                seal: .yellow
            )
        }
        let lvl = profile.level ?? 1
        let band = profile.titleBand?.name
        switch lvl {
        case ...4:
            return FrameStyle(band: band ?? "Premiers pas", border: Theme.border, borderWidth: 1,
                              outer: nil, bgTop: Theme.card, accent: Theme.accent, seal: Color.gray)
        case ...8:
            return FrameStyle(band: band ?? "Apprentissage", border: Color.orange.opacity(0.55), borderWidth: 1.5,
                              outer: nil, bgTop: Color(red: 0.11, green: 0.08, blue: 0.06), accent: .orange, seal: .orange)
        case ...12:
            return FrameStyle(band: band ?? "Exploration", border: Color.green.opacity(0.5), borderWidth: 1.5,
                              outer: nil, bgTop: Color(red: 0.06, green: 0.1, blue: 0.09), accent: .green, seal: .green)
        case ...16:
            return FrameStyle(band: band ?? "Affirmation", border: Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.55), borderWidth: 1.5,
                              outer: nil, bgTop: Color(red: 0.06, green: 0.09, blue: 0.12),
                              accent: Color(red: 0.38, green: 0.65, blue: 0.98), seal: Color(red: 0.38, green: 0.65, blue: 0.98))
        case ...20:
            return FrameStyle(band: band ?? "Expertise", border: Color.purple.opacity(0.55), borderWidth: 1.5,
                              outer: nil, bgTop: Color(red: 0.09, green: 0.06, blue: 0.12), accent: .purple, seal: .purple)
        case ...24:
            return FrameStyle(band: band ?? "Renommée", border: Color.yellow.opacity(0.5), borderWidth: 1.5,
                              outer: Color.yellow.opacity(0.18), bgTop: Color(red: 0.1, green: 0.09, blue: 0.05),
                              accent: .yellow, seal: .yellow)
        case ...28:
            return FrameStyle(band: band ?? "Légende", border: Color.yellow.opacity(0.7), borderWidth: 2,
                              outer: Color.orange.opacity(0.28), bgTop: Color(red: 0.12, green: 0.09, blue: 0.04),
                              accent: .orange, seal: .orange)
        default:
            return FrameStyle(band: band ?? "Mythe", border: Color.purple.opacity(0.7), borderWidth: 2,
                              outer: Color.yellow.opacity(0.3), bgTop: Color(red: 0.09, green: 0.06, blue: 0.12),
                              accent: Color(red: 0.65, green: 0.55, blue: 0.98), seal: .yellow)
        }
    }

    var body: some View {
        let f = frame
        let pct = min(1, max(0, (profile.progressPct ?? 0) / 100.0))
        let into = profile.xpIntoLevel
        let span: Int? = {
            if let s = profile.xpLevelStart, let n = profile.xpLevelNext { return max(1, n - s) }
            return nil
        }()
        let mid: String = {
            if let into, let span { return "\(into) / \(span) XP" }
            return "\(profile.xp ?? 0) XP"
        }()
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(f.band.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(f.accent)
                        .tracking(1.1)
                        .lineLimit(1)
                    Spacer()
                    Text("Nv \(profile.level ?? 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(f.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(f.border))
                }
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.fieldBg).frame(width: 44, height: 44)
                        Circle().stroke(f.seal, lineWidth: 2).frame(width: 44, height: 44)
                        Text(profile.displayIcon).font(.system(size: 20))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if profile.beerMaster == true {
                            Text(profile.prestige?.ribbon ?? "BEER MASTER")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                        HStack {
                            Text(profile.title ?? "Aventurier")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(profile.progressPct ?? 0))%")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(f.accent)
                        }
                        let sub: String = {
                            var bits: [String] = []
                            if let n = profile.classInfo?.name { bits.append(n) }
                            if profile.beerMaster != true, let b = profile.titleBand?.name { bits.append(b) }
                            return bits.joined(separator: " · ")
                        }()
                        if !sub.isEmpty {
                            Text(sub).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                }
                ProgressView(value: pct).tint(f.accent)
                HStack {
                    Text(mid).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(profile.xpToNext.map { "encore \($0)" } ?? "max")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(11)
            .background(
                LinearGradient(colors: [f.bgTop, Theme.card.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(f.border, lineWidth: f.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(f.outer != nil ? 2 : 0)
            .overlay(
                Group {
                    if let o = f.outer {
                        RoundedRectangle(cornerRadius: 16).stroke(o, lineWidth: 3)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
