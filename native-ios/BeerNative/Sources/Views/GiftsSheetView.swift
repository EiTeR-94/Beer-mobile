import SwiftUI

struct GiftsSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var gifts: [GiftIdea] = []
    @State private var partner = ""
    @State private var search = ""
    @State private var filterStyle = ""
    @State private var minRating: Double = 0
    @State private var error: String?

    private var filtered: [GiftIdea] {
        gifts.filter { g in
            if minRating > 0, (g.rating ?? 0) < minRating { return false }
            if !filterStyle.isEmpty, g.style != filterStyle { return false }
            if !search.isEmpty {
                let hay = "\(g.beerName) \(g.brewery ?? "") \(g.style ?? "")".lowercased()
                if !hay.contains(search.lowercased()) { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !partner.isEmpty {
                        Text("Bières notées par \(partner) que tu n'as pas encore goûtées")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    ForEach(filtered) { g in
                        HStack(alignment: .top, spacing: 10) {
                            BeerImage(path: g.photoPath.map { "/beer/photos/\(($0 as NSString).lastPathComponent)" })
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(g.beerName).font(.headline)
                                Text("\(g.brewery ?? "—") · \(g.style ?? "?")").font(.caption).foregroundStyle(Theme.muted)
                                Text("Notée \(BeerFormatters.ratingLabel(g.rating ?? 0)) par \(g.likedBy ?? "?")")
                                    .font(.caption).foregroundStyle(Theme.accent)
                                if let c = g.comment, !c.isEmpty {
                                    Text("« \(c) »").font(.caption).italic()
                                }
                            }
                        }
                        .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if filtered.isEmpty {
                        Text("Aucune idée cadeau avec ces filtres.").foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(partner.isEmpty ? "Idées cadeaux" : "Idées — \(partner)")
            .searchable(text: $search)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        do {
            let data = try await app.api.coupleStats()
            let me = app.user ?? ""
            partner = data.users?.first { $0.username != me }?.username ?? ""
            gifts = (data.giftIdeas ?? []).filter { $0.forUser == me || $0.forUser == nil }
        } catch {
            self.error = error.localizedDescription
        }
    }
}