import SwiftUI

struct GrimoireSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private let tabs = ["Accueil", "Quêtes", "Badges", "Atlas"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(0..<tabs.count, id: \.self) { i in
                        Text(tabs[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

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
            .navigationTitle("Grimoire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await app.refreshRpg() }
        }
    }

    private var emptyMessage: String {
        if app.rpgState?.enabled == false {
            return "Beerquest est désactivé sur le serveur."
        }
        return "Beerquest n’est pas disponible pour ce compte."
    }

    @ViewBuilder
    private func homeTab(_ st: RpgState, _ p: RpgProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BqHudCard(profile: p, onTap: {})
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    stat("🔥", "\(p.streakDays ?? 0)", "Streak")
                    stat("⚡", "\(p.dailyXp ?? 0)/\(p.dailySoftCap ?? 100)", "XP jour")
                    stat("🍺", "\(st.atlas?.totalCheckins ?? 0)", "Check-ins")
                    stat("📜", "\(st.quests?.active?.count ?? 0)", "Quêtes")
                }
                section("📜 Quêtes en cours")
                let active = Array((st.quests?.active ?? []).prefix(3))
                if active.isEmpty {
                    Text("Aucune quête active.").font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    ForEach(active) { QuestCardView(q: $0) }
                }
                if let next = st.nextBadges, !next.isEmpty {
                    section("🏅 Prochains badges")
                    ForEach(next) { BadgeProgressView(b: $0) }
                }
                if let phrase = st.phrase, !phrase.isEmpty {
                    section("🗣️ Le tavernier")
                    Text(phrase).font(.footnote).italic().foregroundStyle(Theme.muted)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func questsTab(_ st: RpgState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("☀️ Journalières")
                let dailies = (st.quests?.active ?? []).filter { $0.kind == "daily" } + (st.quests?.doneToday ?? [])
                if dailies.isEmpty { Text("Rien.").font(.footnote).foregroundStyle(Theme.muted) }
                else { ForEach(dailies) { QuestCardView(q: $0) } }
                section("📅 Hebdomadaires")
                let weeklies = (st.quests?.active ?? []).filter { $0.kind == "weekly" } + (st.quests?.doneWeekly ?? [])
                if weeklies.isEmpty { Text("Aucune.").font(.footnote).foregroundStyle(Theme.muted) }
                else { ForEach(weeklies) { QuestCardView(q: $0) } }
                section("📖 Histoire")
                let story = (st.quests?.active ?? []).filter { $0.kind == "story" }
                if story.isEmpty { Text("Chapitres à venir…").font(.footnote).foregroundStyle(Theme.muted) }
                else { ForEach(story) { QuestCardView(q: $0) } }
            }
            .padding(12)
        }
    }

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
            VStack(alignment: .leading, spacing: 12) {
                // Hero salle des trophées (parité webapp)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SALLE DES TROPHÉES")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.yellow.opacity(0.9))
                        .tracking(1.4)
                    Text("🏅 Collection de badges")
                        .font(.headline).foregroundStyle(Theme.text)
                    Text("Chaque badge a un objectif clair. Touche une tuile pour voir la progression.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                        stat("🏆", "\(nEarned)", "Obtenus")
                        stat("🔒", "\(locked.count)", "À faire")
                        stat("📊", "\(pctAll)%", "Complétion")
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
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.09, blue: 0.05), Theme.card],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.28)))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                badgeGroup("En cours", "⚔️", inProgress)
                badgeGroup("Commun", "⚪", common)
                badgeGroup("Rare", "🔵", rare)
                badgeGroup("Épique", "🟣", epic)
                badgeGroup("Légendaire", "🟡", legendary)
                badgeGroup("Obtenus", "✅", earnedList)
            }
            .padding(12)
        }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(ico) \(title)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(list.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.fieldBg)
                        .clipShape(Capsule())
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(list) { BadgeTileView(b: $0) }
                }
            }
            .padding(10)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func atlasTab(_ st: RpgState, _ p: RpgProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("🗺️ Collection")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    stat("🎨", "\(st.atlas?.stylesCount ?? 0)", "Styles")
                    stat("🌿", "\(st.atlas?.hopsCount ?? 0)", "Houblons")
                    stat("🏭", "\(st.atlas?.breweriesCount ?? 0)", "Brasseries")
                    stat("📷", "\(st.atlas?.photos ?? 0)", "Photos")
                }
                section("⚔️ Classes")
                Text("Une seule classe à la fois. Si la bière colle : +2 XP.")
                    .font(.footnote).foregroundStyle(Theme.muted)
                let equipped = p.classKey
                let aff = st.classAffinity ?? [:]
                ForEach(st.classes ?? []) { c in
                    let key = c.key ?? ""
                    let on = key == equipped
                    Button {
                        Task { await app.equipRpgClass(key) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(c.icon ?? "🍺") \(c.name ?? key)")
                                .font(.headline).foregroundStyle(Theme.text)
                            if let b = c.blurb {
                                Text(b).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Text(on ? "Équipée · \(aff[key] ?? 0)%" : "Toucher pour équiper · \(aff[key] ?? 0)%")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(on ? Theme.accent : Color(red: 0.38, green: 0.65, blue: 0.98))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(on ? Theme.accent : Theme.border)
                        )
                    }
                    .disabled(on || key.isEmpty)
                }
            }
            .padding(12)
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
    }

    private func stat(_ ico: String, _ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(ico)
            Text(v).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text).lineLimit(1)
            Text(l).font(.system(size: 9)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}

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
        let pct = min(1, max(0, (profile.progressPct ?? 0) / 100))
        let into = profile.xpIntoLevel
        let span: Int? = {
            if let a = profile.xpLevelStart, let b = profile.xpLevelNext { return max(1, b - a) }
            return nil
        }()
        let mid: String = {
            if let into, let span { return "\(into) / \(span) XP" }
            return "\(profile.xp ?? 0) XP"
        }()
        let right = profile.xpToNext.map { "encore \($0)" } ?? "max"
        let master = profile.beerMaster == true
        let f = frame

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
                    Text(profile.displayIcon)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Theme.fieldBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(f.seal, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        if master {
                            Text(profile.prestige?.ribbon ?? "BEER MASTER")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.yellow)
                        }
                        HStack {
                            Text(profile.title ?? "Aventurier")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(profile.progressPct ?? 0))%")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(f.accent)
                        }
                        if !subline.isEmpty {
                            Text(subline)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
                ProgressView(value: pct).tint(f.accent)
                HStack {
                    Text(mid).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(right).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(11)
            .background(
                LinearGradient(colors: [f.bgTop, Theme.card.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(f.border, lineWidth: f.borderWidth)
            )
            .overlay(
                Group {
                    if let outer = f.outer {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(outer, lineWidth: 3)
                            .padding(-3)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var subline: String {
        var bits: [String] = []
        if let n = profile.classInfo?.name { bits.append(n) }
        if profile.beerMaster != true, let b = profile.titleBand?.name { bits.append(b) }
        return bits.joined(separator: " · ")
    }
}

struct QuestCardView: View {
    let q: RpgQuest
    var body: some View {
        let done = q.status == "done"
        let tgt = max(1, q.target ?? 1)
        let prog = q.progress ?? 0
        let pct = min(1, Double(prog) / Double(tgt))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((q.kind ?? "quête").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
                    Text(q.title ?? "—").font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                }
                Spacer()
                Text("+\(q.rewardXp ?? 0) XP")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.yellow)
            }
            if let d = q.description {
                Text(d).font(.caption).foregroundStyle(Theme.muted)
            }
            HStack {
                Text(done ? "Terminée" : "En cours")
                    .font(.caption)
                    .foregroundStyle(done ? Color.green : Color(red: 0.38, green: 0.65, blue: 0.98))
                Spacer()
                Text("\(prog)/\(tgt) · \(Int(pct * 100))%")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ProgressView(value: pct).tint(done ? .green : Color(red: 0.38, green: 0.65, blue: 0.98))
        }
        .padding(10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(done ? Color.green : Color(red: 0.38, green: 0.65, blue: 0.98)))
    }
}

struct BadgeProgressView: View {
    let b: RpgBadge
    var body: some View {
        let tgt = max(1, b.target ?? 1)
        let prog = b.progress ?? 0
        let pct = min(1, Double(prog) / Double(tgt))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(b.icon ?? "🏅")
                VStack(alignment: .leading) {
                    Text("\(b.name ?? "Badge") · \(rarityLabelFr(b.rarity))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    if let h = b.hint?.replacingOccurrences(of: "Objectif : ", with: ""), !h.isEmpty {
                        Text(h).font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
            }
            ProgressView(value: pct).tint(Color.purple)
            Text("\(prog)/\(tgt) · \(Int(pct * 100))%").font(.caption2).foregroundStyle(Theme.muted)
        }
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
