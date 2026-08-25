import SwiftUI

// MARK: - Tab button (parité .bq-tab)
// Extrait de GrimoireSheetView.swift — vues de support utilisées par ses onglets.

struct BqTabButton: View {
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

struct NextBadgeRow: View {
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

struct ClassCardView: View {
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
        // Important : ne PAS utiliser Button.disabled(equipped) — iOS applique un filtre gris semi-transparent.
        Group {
            if equipped {
                cardContent
            } else {
                Button(action: onEquip) { cardContent }
                    .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
        .accessibilityLabel(equipped ? "\(c.name ?? "") équipée" : "Équiper \(c.name ?? "")")
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(c.icon ?? "🍺") \(c.name ?? c.key ?? "—")")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if equipped {
                        Text("Équipée")
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
                if let b = c.blurb, !b.isEmpty {
                    Text(b)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                (Text("Quand ").font(.system(size: 9, weight: .heavy)).foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                 + Text(when + " → ").font(.system(size: 11)).foregroundColor(Theme.muted)
                 + Text("+2 XP").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.text))
                (Text("En plus ").font(.system(size: 9, weight: .heavy)).foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                 + Text(special).font(.system(size: 11)).foregroundColor(Theme.muted))
                Text((equipped ? "Active · " : "Si tu l’équipes · ") + habit + " si la bière colle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(equipped ? Color.green : Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Bloc habitude (parité web .bq-class-profile)
            VStack(spacing: 3) {
                Text("Habitude")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .textCase(.uppercase)
                Text("\(aff)%")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(habit)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 72)
            .padding(8)
            .background(Theme.fieldBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        // Fonds 100 % opaques (pas de Color.opacity sur le conteneur équipé)
        .background(
            equipped
                ? Color(red: 0.22, green: 0.17, blue: 0.09) // brun-or plein
                : Theme.card
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    equipped ? Theme.accent
                        : (recommended ? Color(red: 0.38, green: 0.65, blue: 0.98).opacity(0.45) : Theme.border),
                    lineWidth: equipped ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Seules les classes NON équipées sont atténuées (webapp .is-available)
        .opacity(equipped ? 1.0 : 0.82)
        .shadow(color: equipped ? Color.black.opacity(0.35) : .clear, radius: 6, y: 2)
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
