import SwiftUI

struct GiftsSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var gifts: [GiftIdea] = []
    @State private var users: [CoupleStats.CoupleUser] = []
    @State private var partner = ""
    @State private var search = ""
    @State private var filterStyle = ""
    @State private var minRating: Double = 0
    @State private var errorMessage: String?

    private var styleOptions: [String] {
        Array(Set(gifts.compactMap(\.style).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [GiftIdea] {
        gifts.filter { g in
            if minRating > 0 {
                if minRating >= 5, (g.rating ?? 0) < 4.99 { return false }
                else if (g.rating ?? 0) < minRating { return false }
            }
            if !filterStyle.isEmpty, g.style != filterStyle { return false }
            if !search.isEmpty {
                let hay = BeerFormatters.normalizeSearch("\(g.beerName) \(g.brewery ?? "") \(g.style ?? "")")
                if !hay.contains(BeerFormatters.normalizeSearch(search)) { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.error)
                    }
                    coupleStatsRow
                    filtersRow
                    ForEach(filtered) { g in
                        giftCard(g)
                    }
                    if filtered.isEmpty {
                        Text("Aucune idée cadeau avec ces filtres.").foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(partner.isEmpty ? "Idées cadeaux" : "Idées cadeaux — \(partner)")
            .searchable(text: $search, prompt: "Recherche")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private var coupleStatsRow: some View {
        HStack(spacing: 8) {
            ForEach(users) { u in
                VStack(spacing: 2) {
                    Text(u.username == app.user ? "Toi" : u.username)
                        .font(.caption2).foregroundStyle(Theme.muted)
                    Text("\(u.total)")
                        .font(.title3.bold())
                    Text("dégust.").font(.caption2).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var filtersRow: some View {
        HStack {
            Picker("Style", selection: $filterStyle) {
                Text("Tous").tag("")
                ForEach(styleOptions, id: \.self) { s in
                    Text(s).tag(s)
                }
            }
            .pickerStyle(.menu)
            Picker("Note min", selection: $minRating) {
                Text("Toutes").tag(0.0)
                Text("≥ 4 ★").tag(4.0)
                Text("≥ 4.5 ★").tag(4.5)
                Text("= 5 ★").tag(5.0)
            }
            .pickerStyle(.menu)
        }
        .tint(Theme.accent)
    }

    private func giftCard(_ g: GiftIdea) -> some View {
        HStack(alignment: .top, spacing: 10) {
            BeerImage(path: g.photoPath.map { "/beer/photos/\(($0 as NSString).lastPathComponent)" })
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(g.beerName).font(.headline)
                    if (g.rating ?? 0) >= 4.99 {
                        Text("♥").foregroundStyle(Theme.error)
                    }
                }
                Text("\(g.brewery ?? "—") · \(g.style ?? "?")").font(.caption).foregroundStyle(Theme.muted)
                HStack(spacing: 4) {
                    Text("★★★★★").font(.caption).foregroundStyle(Theme.starOff)
                        .overlay(alignment: .leading) {
                            Text("★★★★★").font(.caption).foregroundStyle(Theme.star)
                                .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(g.rating ?? 0)) }
                        }
                    Text(BeerFormatters.ratingLabel(g.rating ?? 0)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Text("Notée par \(g.likedBy ?? "?")")
                    .font(.caption).foregroundStyle(Theme.accent)
                if let d = g.createdAt {
                    Text("Dégustée le \(BeerFormatters.formatDate(d))").font(.caption2).foregroundStyle(Theme.muted)
                }
                if let c = g.comment, !c.isEmpty {
                    Text("« \(c) »").font(.caption).italic()
                }
            }
        }
        .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        do {
            let data = try await app.api.coupleStats()
            let me = app.user ?? ""
            users = data.users ?? []
            partner = data.users?.first { $0.username != me }?.username ?? ""
            gifts = (data.giftIdeas ?? []).filter { $0.forUser == me || $0.forUser == nil }
            errorMessage = nil
        } catch let err {
            errorMessage = err.localizedDescription
        }
    }
}