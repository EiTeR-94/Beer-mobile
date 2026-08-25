import SwiftUI

// HUD card (accueil app) — extrait de GrimoireSheetView.swift, utilisé par MainView.

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
