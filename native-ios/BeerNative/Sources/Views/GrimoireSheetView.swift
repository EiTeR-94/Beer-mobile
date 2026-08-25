import SwiftUI

// MARK: - Grimoire (parité webapp beerquest.js / beerquest.css)
//
// Vues de support (BqTabButton, QuestCardView, NextBadgeRow, ClassCardView,
// FlowStyleChips, BadgeProgressView, BadgeTileView) extraites vers
// GrimoireSupportViews.swift. BqHudCard (utilisé par MainView) extrait vers
// BqHudCard.swift.

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
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grimoire")
                            .font(.system(size: Theme.Font.h1, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("Beerquest · taverne personnelle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 4)
                    BeerGhostButton("Fermer") { dismiss() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.border).frame(height: 1)
                }

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
                        statTile(
                            p.dailySoftCapped == true ? "⛔" : "⚡",
                            "\(p.dailyXp ?? 0)/\(p.dailySoftCap ?? 100)",
                            p.dailySoftCapped == true ? "Soft cap" : "XP du jour"
                        )
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
        let equippedLabel: String = {
            guard let eq = equipped else { return "" }
            return "\(eq.icon ?? "🍺") \(eq.name ?? eq.key ?? "")"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        let recLabel: String = {
            guard let rk = recKey, rk != equippedKey,
                  let rec = classes.first(where: { $0.key == rk }) else { return "" }
            return "\(rec.icon ?? "🍺") \(rec.name ?? rk)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }()

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
                    if !equippedLabel.isEmpty || !recLabel.isEmpty {
                        HStack(spacing: 6) {
                            if !equippedLabel.isEmpty {
                                Text("Équipée · \(equippedLabel)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.accent.opacity(0.14))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            if !recLabel.isEmpty {
                                Text("Plus jouée · \(recLabel)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.12))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
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
