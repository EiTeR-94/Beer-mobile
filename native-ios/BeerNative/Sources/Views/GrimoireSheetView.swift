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
        let earned = badges.filter { $0.earned == true }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(earned) / \(badges.count) badges")
                    .font(.footnote).foregroundStyle(Theme.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(badges) { BadgeTileView(b: $0) }
                }
            }
            .padding(12)
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

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(profile.displayIcon)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(Theme.fieldBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(master ? Color.yellow : Theme.accent))
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
                                .foregroundStyle(Color.yellow)
                        }
                        Text(subline)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                ProgressView(value: pct)
                    .tint(master ? .yellow : Theme.accent)
                HStack {
                    Text(mid).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(right).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(10)
            .background(master ? Color(red: 0.47, green: 0.21, blue: 0.06).opacity(0.35) : Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(master ? Color.yellow.opacity(0.55) : Theme.border)
            )
        }
        .buttonStyle(.plain)
    }

    private var subline: String {
        var bits = ["Nv \(profile.level ?? 1)"]
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
        VStack(spacing: 4) {
            Text(b.icon ?? "🏅").font(.title2)
            Text(b.name ?? "—").font(.caption2.weight(.bold)).foregroundStyle(Theme.text).lineLimit(2)
            Text(rarityLabelFr(b.rarity)).font(.system(size: 9)).foregroundStyle(Theme.muted)
            Text(earned ? "✓ Obtenu" : "\(prog)/\(tgt)")
                .font(.system(size: 10))
                .foregroundStyle(earned ? Color.green : Theme.muted)
            if !earned {
                ProgressView(value: pct).tint(Color.purple)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(earned ? Color.purple : Theme.border))
    }
}
