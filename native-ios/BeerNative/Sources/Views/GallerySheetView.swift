import SwiftUI

struct GallerySheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CheckinItem] = []
    @State private var styles: [StyleOption] = []
    @State private var search = ""
    @State private var filterStyle = ""
    @State private var filterRating: Double = 0
    @State private var filterPeriod = ""
    @State private var selected: CheckinItem?
    @State private var editing: CheckinItem?
    @State private var loading = false

    private var withPhotos: [CheckinItem] {
        items.filter { ($0.photoURL?.isEmpty == false) }
            .filter { item in
                if !filterStyle.isEmpty, item.style != filterStyle { return false }
                if filterRating > 0, item.rating < filterRating { return false }
                if !search.isEmpty {
                    let hay = BeerFormatters.normalizeSearch("\(item.beerName) \(item.brewery ?? "") \(item.style ?? "")")
                    if !hay.contains(BeerFormatters.normalizeSearch(search)) { return false }
                }
                return true
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    filtersRow
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(withPhotos) { item in
                            Button { selected = item } label: {
                                BeerImage(path: item.photoURL)
                                    .frame(height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .bottom) {
                                        Text(item.beerName)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .padding(4)
                                            .frame(maxWidth: .infinity)
                                            .background(.black.opacity(0.55))
                                            .foregroundStyle(.white)
                                    }
                            }
                        }
                    }
                    if loading && items.isEmpty {
                        ProgressView("Chargement…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if withPhotos.isEmpty {
                        BeerEmptyState(
                            icon: "📷",
                            title: "Aucune photo",
                            subtitle: "Les dégustations avec photo apparaîtront ici."
                        )
                    }
                }
                .padding(12)
            }
            .background(Theme.bg)
            .navigationTitle("Galerie photos")
            .searchable(text: $search, prompt: "nom, brasserie…")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { await bootstrap() }
            .refreshable { await reload() }
            .onChange(of: filterStyle, perform: { _ in Task { await reload() } })
            .onChange(of: filterRating, perform: { _ in Task { await reload() } })
            .onChange(of: filterPeriod, perform: { _ in Task { await reload() } })
            .sheet(item: $selected) { item in
                CheckinDetailView(
                    item: item,
                    onRetaste: {
                        selected = nil
                        dismiss()
                        app.startQuickRate(item)
                    },
                    onEdit: { editing = item; selected = nil }
                )
            }
            .sheet(item: $editing) { item in
                CheckinEditView(item: item) { Task { await reload() } }
            }
        }
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
            HStack(spacing: 6) {
                FilterChip(title: "Toutes notes", selected: filterRating == 0) { filterRating = 0 }
                FilterChip(title: "3 ★+", selected: filterRating == 3) { filterRating = 3 }
                FilterChip(title: "4 ★+", selected: filterRating == 4) { filterRating = 4 }
                FilterChip(title: "5 ★", selected: filterRating == 5) { filterRating = 5 }
            }
        }
    }

    private func bootstrap() async {
        styles = (try? await app.api.styles()) ?? []
        await reload()
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var all: [CheckinItem] = []
        for offset in stride(from: 0, to: 150, by: 50) {
            let batch = (try? await app.api.checkins(
                q: search.trimmingCharacters(in: .whitespaces),
                style: filterStyle,
                minRating: filterRating,
                period: filterPeriod,
                limit: 50,
                offset: offset
            )) ?? []
            all.append(contentsOf: batch)
            if batch.count < 50 { break }
        }
        items = all
    }
}