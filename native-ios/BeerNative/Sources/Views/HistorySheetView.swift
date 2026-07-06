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
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let stats, stats.total > 0 { statsRow(stats) }
                    filtersRow
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.error) }
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
                        LazyVStack(spacing: 10) {
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
                        Button(loading ? "Chargement…" : "Charger 10 de plus") {
                            Task { await load(append: true) }
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("📷 Galerie") {
                        dismiss()
                        onOpenGallery?()
                    }
                }
            }
            .searchable(text: $search, prompt: "nom, brasserie, style…")
            .onChange(of: search, perform: { _ in Task { await reload() } })
            .onChange(of: filterStyle, perform: { _ in Task { await reload() } })
            .onChange(of: filterRating, perform: { _ in Task { await reload() } })
            .onChange(of: filterPeriod, perform: { _ in Task { await reload() } })
            .task {
                if !initialSearch.isEmpty && search.isEmpty {
                    search = initialSearch
                }
                await bootstrap()
            }
            .refreshable { await reload() }
            .sheet(item: $selected) { item in
                CheckinDetailView(item: item, onRetaste: {
                    selected = nil
                    dismiss()
                    app.startRetaste(item)
                }, onEdit: { editing = item; selected = nil })
            }
            .sheet(item: $editing) { item in
                CheckinEditView(item: item) { Task { await reload() } }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func statsRow(_ s: HistoryStats) -> some View {
        HStack(spacing: 8) {
            statCell("\(s.total)", "dégust.")
            statCell(BeerFormatters.ratingLabel(s.avgRating ?? 0), "moyenne")
            statCell(s.topStyles?.first?.style ?? "—", "style")
            statCell(s.last?.beerName ?? "—", "dernière", small: true)
        }
    }

    private func statCell(_ value: String, _ label: String, small: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: small ? 11 : 15, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filtersRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(title: "Tous styles", selected: filterStyle.isEmpty) { filterStyle = "" }
                    ForEach(styles.filter { !$0.value.isEmpty }) { s in
                        FilterChip(title: s.label, selected: filterStyle == s.value) { filterStyle = s.value }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(title: "Toutes notes", selected: filterRating == 0) { filterRating = 0 }
                    ForEach([3.0, 4.0, 5.0], id: \.self) { v in
                        FilterChip(
                            title: "\(BeerFormatters.ratingLabel(v)) ★+",
                            selected: filterRating == v
                        ) { filterRating = v }
                    }
                }
            }
            HStack(spacing: 6) {
                FilterChip(title: "Tout", selected: filterPeriod.isEmpty) { filterPeriod = "" }
                FilterChip(title: "7 j", selected: filterPeriod == "week") { filterPeriod = "week" }
                FilterChip(title: "30 j", selected: filterPeriod == "month") { filterPeriod = "month" }
                FilterChip(title: "1 an", selected: filterPeriod == "year") { filterPeriod = "year" }
            }
        }
    }

    private func historyCard(_ item: CheckinItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button { selected = item } label: {
                    BeerImage(path: item.photoURL)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.beerName).font(.headline).foregroundStyle(Theme.text)
                        if app.isAdmin && (item.hiddenFromPartner == true) {
                            Text("Privée").font(.caption2).padding(4).background(Theme.accent.opacity(0.2)).clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 4) {
                        Text("★★★★★").font(.caption).foregroundStyle(Theme.starOff)
                            .overlay(alignment: .leading) {
                                Text("★★★★★").font(.caption).foregroundStyle(Theme.star)
                                    .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(item.rating)) }
                            }
                        Text(BeerFormatters.ratingLabel(item.rating)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    Text("\(item.brewery ?? "—") · \(item.style ?? "?") · \(BeerFormatters.formatDate(item.createdAt))")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let flavors = item.flavors, !flavors.isEmpty {
                        Text(flavors.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let comment = item.comment, !comment.isEmpty {
                        Text("« \(comment) »").font(.caption).italic().padding(8)
                            .background(Theme.bg.opacity(0.5))
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
                    }
                }
            }
            HStack(spacing: 6) {
                Button("Noter à nouveau") { dismiss(); app.startRetaste(item, step: 2) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                Button("Rapide") { dismiss(); app.startQuickRate(item) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Modifier") { editing = item }.buttonStyle(.bordered).controlSize(.small)
                Button("Supprimer", role: .destructive) { Task { await delete(item) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .beerShadow()
    }

    private func bootstrap() async {
        styles = (try? await app.api.styles()) ?? []
        await reload()
    }

    private func reload() async {
        offset = 0
        hasMore = true
        items = []
        await load(append: false)
        stats = try? await app.api.stats()
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
            if append { items.append(contentsOf: batch) } else { items = batch }
            offset = items.count
            hasMore = batch.count == pageSize
        } catch let err {
            error = err.localizedDescription
        }
    }

    private func delete(_ item: CheckinItem) async {
        do {
            try await app.api.deleteCheckin(id: item.id)
            items.removeAll { $0.id == item.id }
            app.showToast("Dégustation supprimée", variant: .success)
        } catch let err {
            self.error = err.localizedDescription
            app.showToast(err.localizedDescription, variant: .error)
        }
    }
}