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
        BeerOverlayScreen(
            title: partner.isEmpty ? "Idées cadeaux" : "Idées cadeaux — \(partner)",
            onClose: { dismiss() }
        ) {
            VStack(spacing: 12) {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.error)
                }
                coupleStatsRow
                BeerGiftsFiltersRow(
                    search: $search,
                    filterStyle: $filterStyle,
                    minRating: $minRating,
                    styleOptions: styleOptions
                )

                if filtered.isEmpty {
                    Text("Aucune idée cadeau avec ces filtres.")
                        .font(.system(size: Theme.Font.lead * 0.94))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { g in
                            giftCard(g)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var coupleStatsRow: some View {
        HStack(spacing: 8) {
            ForEach(users) { u in
                VStack(spacing: 2) {
                    Text(u.username == app.user ? "Toi" : u.username)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Text("\(u.total)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("dégust.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(9)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func giftCard(_ g: GiftIdea) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BeerImage(path: g.photoPath.map { "/beer/photos/\(($0 as NSString).lastPathComponent)" })
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(g.beerName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if (g.rating ?? 0) >= 4.99 {
                        Text("♥").foregroundStyle(Theme.error)
                    }
                }
                Text("\(g.brewery ?? "—") · \(g.style ?? "?")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 4) {
                    Text("★★★★★").font(.system(size: 11)).foregroundStyle(Theme.starOff)
                        .overlay(alignment: .leading) {
                            Text("★★★★★").font(.system(size: 11)).foregroundStyle(Theme.star)
                                .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(g.rating ?? 0)) }
                        }
                    Text(BeerFormatters.ratingLabel(g.rating ?? 0))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text("Notée par \(g.likedBy ?? "?")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                if let d = g.createdAt {
                    Text("Dégustée le \(BeerFormatters.formatDate(d))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                if let c = g.comment, !c.isEmpty {
                    Text("« \(c) »")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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