import SwiftUI

// MARK: - Overlays célébrations + intro Beerquest

struct RpgCelebrationOverlay: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            if app.showRpgIntro {
                RpgIntroCard(
                    onDiscover: { app.dismissRpgIntro(openGrimoire: true) },
                    onLater: { app.dismissRpgIntro(openGrimoire: false) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(2)
            }
            if let celeb = app.rpgCelebration {
                switch celeb {
                case .levelUp(let loot):
                    RpgLevelUpCard(loot: loot) {
                        app.dismissRpgCelebration()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(3)
                case .badge(let badge):
                    RpgBadgeUnlockCard(badge: badge) { openGrimoire in
                        app.dismissRpgCelebration(openGrimoire: openGrimoire)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(3)
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: app.rpgCelebration?.id)
        .animation(.easeOut(duration: 0.25), value: app.showRpgIntro)
    }
}

// MARK: - Intro

private struct RpgIntroCard: View {
    let onDiscover: () -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onLater)
            VStack(alignment: .leading, spacing: 14) {
                Text("⚔ BEERQUEST")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.yellow.opacity(0.95))
                    .tracking(1.2)
                Text("Tes dégustations font progresser un grimoire")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("XP, quêtes et badges s’ajoutent à chaque bière notée. Le scan et la note ne changent pas.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Plus tard", action: onLater)
                        .buttonStyle(.bordered)
                        .tint(Theme.muted)
                    Button("Découvrir", action: onDiscover)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.yellow.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(24)
        }
    }
}

// MARK: - Level up

private struct RpgLevelUpCard: View {
    let loot: RpgLoot
    let onDismiss: () -> Void
    @State private var barPct: CGFloat = 0

    private var oldLv: Int { loot.oldLevel ?? max(1, (loot.level ?? 1) - 1) }
    private var newLv: Int { loot.level ?? 1 }
    private var gained: Int {
        loot.levelsGained ?? max(1, newLv - oldLv)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("LEVEL UP")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.yellow)
                    .tracking(2)
                Text(gained > 1 ? "Niveaux \(oldLv) → \(newLv)" : "Niveau \(newLv)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(gained > 1 ? "+\(gained) niveaux d’un coup" : "Lv \(oldLv) → Lv \(newLv)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.yellow.opacity(0.9))
                if loot.titleChanged == true, let old = loot.oldTitle, let t = loot.title {
                    Text("\(old) → \(t)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                } else if let t = loot.title, !t.isEmpty {
                    Text(t)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
                Text(loot.phraseLevelUp ?? loot.phrase ?? "Le tavernier hoche la tête.")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fieldBg)
                        Capsule()
                            .fill(LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * barPct))
                    }
                }
                .frame(height: 12)
                .padding(.horizontal, 4)
                Button("Continuer", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.14, blue: 0.06), Theme.card],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.yellow.opacity(0.55), lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) {
                barPct = CGFloat((loot.progressPct ?? 0) / 100.0).clamped(to: 0...1)
            }
        }
    }
}

// MARK: - Badge unlock

private struct RpgBadgeUnlockCard: View {
    let badge: RpgBadge
    let onDismiss: (Bool) -> Void

    private var rarity: String { (badge.rarity ?? "common").lowercased() }
    private var rarityColor: Color {
        switch rarity {
        case "legendary": return .orange
        case "epic": return .purple
        case "rare": return Color(red: 0.38, green: 0.65, blue: 0.98)
        default: return Theme.muted
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("BADGE · \(rarity.uppercased())")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(rarityColor)
                    .tracking(1.4)
                Text(badge.icon ?? "🏅")
                    .font(.system(size: 52))
                Text(badge.name ?? "Badge")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text(rarityLabelFr(badge.rarity))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(rarityColor)
                if let lore = badge.lore ?? badge.hint, !lore.isEmpty {
                    Text(lore)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                Text(badge.unlockPhrase ?? "Un badge s’ajoute au grimoire.")
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Voir le grimoire") { onDismiss(true) }
                        .buttonStyle(.bordered)
                    Button("Super !") { onDismiss(false) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(
                LinearGradient(
                    colors: [rarityColor.opacity(0.22), Theme.card],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(rarityColor.opacity(0.65), lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
    }
}

// MARK: - Badge detail sheet

struct RpgBadgeDetailView: View {
    let badge: RpgBadge
    let onClose: () -> Void

    private var rarity: String { (badge.rarity ?? "common").lowercased() }
    private var rarityColor: Color {
        switch rarity {
        case "legendary": return .orange
        case "epic": return .purple
        case "rare": return Color(red: 0.38, green: 0.65, blue: 0.98)
        default: return Theme.muted
        }
    }
    private var tgt: Int { max(1, badge.target ?? 1) }
    private var prog: Int { badge.progress ?? 0 }
    private var pct: Double { min(1, Double(prog) / Double(tgt)) }
    private var earned: Bool { badge.earned == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(badge.icon ?? "🏅").font(.system(size: 56))
                    Text(badge.name ?? "Badge")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text(rarityLabelFr(badge.rarity))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(rarityColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(rarityColor.opacity(0.15))
                        .clipShape(Capsule())
                    if earned {
                        Text("✓ Obtenu")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.green)
                        if let at = badge.earnedAt, !at.isEmpty {
                            Text(at).font(.caption).foregroundStyle(Theme.muted)
                        }
                    } else {
                        ProgressView(value: pct)
                            .tint(prog > 0 ? .yellow : rarityColor)
                        Text("\(prog) / \(tgt) · \(Int(pct * 100))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        if let rem = badge.remaining, rem > 0 {
                            Text("Encore \(rem)").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    if let lore = badge.lore, !lore.isEmpty {
                        detailBlock(title: "Lore", text: lore)
                    }
                    if let hint = badge.hint, !hint.isEmpty {
                        detailBlock(title: "Objectif", text: hint)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .navigationTitle("Badge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", action: onClose)
                }
            }
        }
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
