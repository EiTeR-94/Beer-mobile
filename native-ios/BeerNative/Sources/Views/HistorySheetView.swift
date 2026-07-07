import SwiftUI

struct HistorySheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var initialSearch: String = ""
    var onOpenGallery: (() -> Void)?

    @State private var items: [CheckinItem] = []
    @State private var stats: HistoryStats?
    @State private var styles: [StyleOption] = []
    @State private var search = ""
    @State private var filterStyle = ""
    @State private var filterRating: Double = 0
    @State private var filterPeriod = ""
    @State private var offset = 0
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var selected: CheckinItem?
    @State private var editing: CheckinItem?

    private let pageSize = 10

    var body: some View {
        BeerOverlayScreen(
            title: "Historique",
            onClose: { dismiss() },
            trailing: [
                .ghost("📷 Galerie") {
                    dismiss()
                    onOpenGallery?()
                },
            ]
        ) {
            VStack(spacing: 10) {
                if let stats, stats.total > 0 { statsRow(stats) }
                BeerHistoryFiltersRow(
                    filterStyle: $filterStyle,
                    filterRating: $filterRating,
                    filterPeriod: $filterPeriod,
                    styles: styles
                )
                BeerHistorySearchField(text: $search)

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.error)
                }
                if loading && items.isEmpty {
                    ProgressView("Chargement…")
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if items.isEmpty {
                    BeerEmptyState(
                        icon: "🍺",
                        title: "Aucune dégustation",
                        subtitle: search.isEmpty
                            ? "Note ta première bière depuis l'accueil."
                            : "Aucun résultat pour « \(search) »."
                    )
                } else {
                    LazyVStack(spacing: 11) {
                        ForEach(items) { item in
                            historyCard(item)
                                .onAppear {
                                    if item.id == items.last?.id, hasMore, !loading {
                                        Task { await load(append: true) }
                                    }
                                }
                        }
                    }
                }
                if hasMore && !items.isEmpty {
                    BeerLoadMoreButton(title: loading ? "Chargement…" : "Charger 10 de plus") {
                        Task { await load(append: true) }
                    }
                    .disabled(loading)
                    .opacity(loading ? 0.45 : 1)
                }
            }
        }
        .onChange(of: search, perform: { _ in Task { await reload() } })
        .onChange(of: filterStyle, perform: { _ in Task { await reload() } })
        .onChange(of: filterRating, perform: { _ in Task { await reload() } })
        .onChange(of: filterPeriod, perform: { _ in Task { await reload() } })
        .task {
            if !initialSearch.isEmpty && search.isEmpty { search = initialSearch }
            await bootstrap()
        }
        .refreshable { await reload() }
        .fullScreenCover(item: $selected) { item in
            CheckinDetailView(
                item: item,
                onRetaste: {
                    selected = nil
                    dismiss()
                    app.startRetaste(item)
                },
                onEdit: { editing = item; selected = nil }
            )
            .environmentObject(app)
        }
        .sheet(item: $editing) { item in
            CheckinEditView(item: item) { Task { await reload() } }
                .beerSheetChrome()
        }
    }

    private func statsRow(_ s: HistoryStats) -> some View {
        HStack(spacing: 8) {
            statCell("\(s.total)", "dégust.")
            statCell(BeerFormatters.ratingLabel(s.avgRating ?? 0), "moyenne")
            statCell(s.topStyles?.first?.style ?? "—", "top style")
            statCell(s.last?.beerName ?? "—", "dernière", small: true)
        }
    }

    private func statCell(_ value: String, _ label: String, small: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: small ? 11 : 15, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func historyCard(_ item: CheckinItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { selected = item } label: {
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if item.photoURL != nil {
                            BeerImage(path: item.photoURL)
                                .frame(width: 88, height: 88)
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .background(Theme.bg)
                                .frame(width: 88, height: 88)
                                .overlay(Text("🍺").font(.title2))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.beerName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            Text("★★★★★").font(.system(size: 11)).foregroundStyle(Theme.starOff)
                                .overlay(alignment: .leading) {
                                    Text("★★★★★").font(.system(size: 11)).foregroundStyle(Theme.star)
                                        .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(item.rating)) }
                                }
                            Text(BeerFormatters.ratingLabel(item.rating))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text("\(item.brewery ?? "—") · \(item.style ?? "Inconnu") · \(BeerFormatters.formatDate(item.createdAt))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                        if let flavors = item.flavors, !flavors.isEmpty {
                            Text(flavors.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        if let hops = item.hops, !hops.isEmpty {
                            Text("Houblons : \(hops.joined(separator: ", "))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        if let comment = item.comment, !comment.isEmpty {
                            Text("« \(comment) »")
                                .font(.system(size: 13.5))
                                .italic()
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.bg.opacity(0.55))
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(Theme.accent).frame(width: 3)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            FlowLayout(spacing: 6) {
                BeerCompactButton(title: "Noter à nouveau", primary: true) {
                    dismiss()
                    app.startRetaste(item, step: 2)
                }
                BeerCompactButton(title: "Rapide") {
                    dismiss()
                    app.startQuickRate(item)
                }
                BeerCompactButton(title: "Modifier") { editing = item }
                BeerCompactButton(title: "Supprimer", destructive: true) {
                    Task { await delete(item) }
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func bootstrap() async {
        if let cached = app.cache.load([StyleOption].self, name: CacheKey.styles) {
            styles = cached
        }
        if let live = try? await app.api.styles(), !live.isEmpty {
            styles = live
            app.cache.save(live, name: CacheKey.styles)
        }
        if items.isEmpty, let cached = app.cache.load([CheckinItem].self, name: CacheKey.historyCheckins) {
            items = cached
            stats = app.cache.load(HistoryStats.self, name: CacheKey.historyStats)
        }
        await reload()
    }

    private func reload() async {
        offset = 0
        hasMore = true
        await load(append: false)
        if let live = try? await app.api.stats() {
            stats = live
            app.cache.save(live, name: CacheKey.historyStats)
        } else if stats == nil {
            stats = app.cache.load(HistoryStats.self, name: CacheKey.historyStats)
        }
    }

    private func load(append: Bool) async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let batch = try await app.api.checkins(
                q: search.trimmingCharacters(in: .whitespaces),
                style: filterStyle,
                minRating: filterRating,
                period: filterPeriod,
                limit: pageSize,
                offset: append ? offset : 0
            )
            if append {
                items.append(contentsOf: batch)
            } else {
                items = batch
                app.cache.save(batch, name: CacheKey.historyCheckins)
            }
            offset = items.count
            hasMore = batch.count == pageSize
        } catch let err {
            if !append, let cached = app.cache.load([CheckinItem].self, name: CacheKey.historyCheckins) {
                items = cached
                error = "Données en cache — \(app.networkStatus.label.lowercased())"
            } else {
                error = err.localizedDescription
            }
        }
    }

    private func delete(_ item: CheckinItem) async {
        do {
            try await app.api.deleteCheckin(id: item.id)
            items.removeAll { $0.id == item.id }
            app.showToast("Dégustation supprimée", variant: .success)
        } catch let err {
            error = err.localizedDescription
            app.showToast(err.localizedDescription, variant: .error)
        }
    }
}