import SwiftUI

/// Admin Beerquest minimal : liste joueurs, XP, reset journalier.
struct BeerquestAdminSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var players: [RpgAdminPlayer] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: RpgAdminPlayer?
    @State private var busyUser: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Chargement…").tint(Theme.accent)
                } else if let error {
                    Text(error).foregroundStyle(Theme.error).padding()
                } else if players.isEmpty {
                    Text("Aucun joueur.").foregroundStyle(Theme.muted).padding()
                } else {
                    List {
                        ForEach(players) { p in
                            Button {
                                selected = p
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.username ?? "—")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Theme.text)
                                        Text(metaLine(p))
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text("Nv \(p.level ?? 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.yellow)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("⚔ Beerquest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await reload() }
            .sheet(item: $selected) { p in
                playerDetail(p)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func metaLine(_ p: RpgAdminPlayer) -> String {
        var bits: [String] = []
        bits.append("\(p.xp ?? 0) XP")
        if let t = p.title, !t.isEmpty { bits.append(t) }
        bits.append("\(p.badgeCount ?? 0) badges")
        if p.isInvite == true { bits.append("invité") }
        if p.beerMaster == true { bits.append("Master") }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder
    private func playerDetail(_ p: RpgAdminPlayer) -> some View {
        let name = p.username ?? ""
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(name).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                Text(metaLine(p)).font(.footnote).foregroundStyle(Theme.muted)
                Text("Ajuster l’XP").font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                HStack(spacing: 8) {
                    ForEach([-50, -10, 10, 50], id: \.self) { d in
                        Button(d > 0 ? "+\(d)" : "\(d)") {
                            Task { await adjustXp(name, d) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busyUser != nil)
                    }
                }
                Button("Reset XP du jour") {
                    Task { await resetDaily(name) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(busyUser != nil)
                if busyUser == name {
                    ProgressView().tint(Theme.accent)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
