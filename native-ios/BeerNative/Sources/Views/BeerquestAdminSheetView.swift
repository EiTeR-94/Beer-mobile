import SwiftUI

/// Admin Beerquest — parité visuelle webapp (cartes joueurs, pills, barre XP).
struct BeerquestAdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var players: [RpgAdminPlayer] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: RpgAdminPlayer?
    @State private var busyUser: String?
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
                // Head
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
                    Button {
                        Task { await reload() }
                    } label: {
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

                // Search
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

                Group {
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
                                    Button { selected = p } label: {
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
            }
            .background(Theme.bg)
            .navigationBarHidden(true)
            .task { await reload() }
            .sheet(item: $selected) { p in
                playerDetail(p)
                    .preferredColorScheme(.dark)
                    .presentationDetents([.medium, .large])
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
                    if p.isInvite == true {
                        adminPill("invité", kind: .invite)
                    }
                    if p.orphan == true {
                        adminPill("orphelin", kind: .off)
                    }
                    if p.allowed == false {
                        adminPill("RPG bloqué", kind: .off)
                    } else {
                        adminPill("RPG OK", kind: .on)
                    }
                    if p.hasProfile == false {
                        adminPill("sans profil", kind: .muted)
                    }
                    if p.suspicionFlagged == true || (p.suspicionScore ?? 0) >= 12 {
                        adminPill("⚠ susp \(p.suspicionScore ?? 0)", kind: .off)
                    } else if (p.suspicionScore ?? 0) > 0 {
                        adminPill("susp \(p.suspicionScore ?? 0)", kind: .muted)
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
        var bits: [String] = []
        bits.append("Lv \(p.level ?? 1)")
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

    private func adminPill(_ text: String, kind: PillKind) -> some View {
        let fg: Color
        let bg: Color
        let border: Color
        switch kind {
        case .on:
            fg = Color.green; bg = Color.green.opacity(0.12); border = Color.green.opacity(0.35)
        case .off:
            fg = Theme.error; bg = Theme.error.opacity(0.12); border = Theme.error.opacity(0.35)
        case .invite:
            fg = Color(red: 0.38, green: 0.65, blue: 0.98)
            bg = fg.opacity(0.12); border = fg.opacity(0.4)
        case .muted:
            fg = Theme.muted; bg = Theme.fieldBg; border = Theme.border
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

    @ViewBuilder
    private func playerDetail(_ p: RpgAdminPlayer) -> some View {
        let name = p.username ?? ""
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                        if p.isInvite == true { adminPill("invité", kind: .invite) }
                        if p.allowed != false { adminPill("RPG OK", kind: .on) }
                        else { adminPill("RPG bloqué", kind: .off) }
                    }
                    // Stats chips
                    FlowWrap(items: [
                        "Lv \(p.level ?? 1)",
                        "\(p.xp ?? 0) XP",
                        "\(p.checkins ?? 0) check-ins",
                        "🔥 \(p.streakDays ?? 0) j",
                        "\(p.badgeCount ?? 0) badges",
                        p.title ?? "—",
                    ])

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ajuster l’XP")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.text)
                        Text("Modifie l’XP du joueur (comme sur la webapp).")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            ForEach([-50, -10, 10, 50], id: \.self) { d in
                                Button(d > 0 ? "+\(d)" : "\(d)") {
                                    Task { await adjustXp(name, d) }
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .disabled(busyUser != nil)
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button {
                        Task { await resetDaily(name) }
                    } label: {
                        Text(busyUser == name ? "…" : "Reset XP du jour")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [Theme.accent, Color.orange], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busyUser != nil)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Joueur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { selected = nil }
                }
            }
        }
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

    private func adjustXp(_ user: String, _ delta: Int) async {
        busyUser = user
        defer { busyUser = nil }
        do {
            let ok = try await app.api.adminRpgAdjustXp(username: user, delta: delta)
            if ok {
                app.showToast("XP \(delta > 0 ? "+" : "")\(delta) pour \(user)", variant: .success, label: "Beerquest")
                await reload()
                if let refreshed = players.first(where: { $0.username == user }) {
                    selected = refreshed
                }
            } else {
                app.showToast("Échec XP", variant: .error)
            }
        } catch {
            app.showToast("Échec XP", variant: .error)
        }
    }

    private func resetDaily(_ user: String) async {
        busyUser = user
        defer { busyUser = nil }
        do {
            let ok = try await app.api.adminRpgResetDaily(username: user)
            if ok {
                app.showToast("Reset journalier \(user)", variant: .success, label: "Beerquest")
                await reload()
            } else {
                app.showToast("Échec reset", variant: .error)
            }
        } catch {
            app.showToast("Échec reset", variant: .error)
        }
    }
}

/// Simple wrap layout for stat chips
private struct FlowWrap: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.self) { s in
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
    }
}
