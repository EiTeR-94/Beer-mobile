import SwiftUI

struct GallerySheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CheckinItem] = []
    @State private var styles: [StyleOption] = []
    @State private var filterStyle = ""
    @State private var filterRating: Double = 0
    @State private var filterPeriod = ""
    @State private var selected: CheckinItem?
    @State private var editing: CheckinItem?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var galleryOffset = 0
    @State private var galleryHasMore = true
    private let galleryPageSize = 50

    private var withPhotos: [CheckinItem] {
        items.filter { ($0.photoURL?.isEmpty == false) }
    }

    var body: some View {
        BeerOverlayScreen(title: "Galerie photos", onClose: { dismiss() }, onRefresh: { await reload(force: true) }) {
            VStack(spacing: 10) {
                BeerHistoryFiltersRow(
                    filterStyle: $filterStyle,
                    filterRating: $filterRating,
                    filterPeriod: $filterPeriod,
                    styles: styles
                )

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.muted)
                }

                HStack {
                    Text("\(withPhotos.count) photos")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if !filterStyle.isEmpty || filterRating > 0 || !filterPeriod.isEmpty {
                        Button("Réinitialiser filtres") {
                            filterStyle = ""
                            filterRating = 0
                            filterPeriod = ""
                        }
                        .font(.caption)
                        .tint(Theme.accent)
                    }
                }
                .padding(.horizontal, 4)

                if loading && withPhotos.isEmpty {
                    // meilleur skeleton loading
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(0..<9, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.card)
                                .frame(height: 118)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Theme.muted.opacity(0.15))
                                )
                        }
                    }
                } else if withPhotos.isEmpty {
                    BeerEmptyState(
                        icon: "📷",
                        title: "Aucune photo",
                        subtitle: "Les dégustations avec photo apparaîtront ici."
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(withPhotos) { item in
                            Button { selected = item } label: {
                                GalleryCell(item: item)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.id == withPhotos.last?.id, galleryHasMore, !loading {
                                    Task { await loadGallery(append: true) }
                                }
                            }
                        }
                    }
                    if galleryHasMore && !withPhotos.isEmpty {
                        BeerLoadMoreButton(title: loading ? "Chargement…" : "Charger plus de photos") {
                            Task { await loadGallery(append: true) }
                        }
                    }
                }
            }
        }
        .onChange(of: filterStyle, perform: { _ in Task { await reload(force: false) } })
        .onChange(of: filterRating, perform: { _ in Task { await reload(force: false) } })
        .onChange(of: filterPeriod, perform: { _ in Task { await reload(force: false) } })
        .task { await bootstrap() }
        .fullScreenCover(item: $selected) { item in
            CheckinDetailView(
                item: item,
                onRetaste: {
                    selected = nil
                    dismiss()
                    app.startQuickRate(item)
                },
                onEdit: { editing = item; selected = nil }
            )
            .environmentObject(app)
        }
        .sheet(item: $editing) { item in
            CheckinEditView(item: item) { Task { await reload(force: true) } }
                .beerSheetChrome()
        }
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
        }
        await reload(force: true)
    }

    private func reload(force: Bool) async {
        if loading, !force { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        galleryOffset = 0
        galleryHasMore = true
        items = []
        await loadGallery(append: false)
    }

    private func loadGallery(append: Bool) async {
        guard !loading || append else { return }
        if !append { loading = true }
        errorMessage = nil
        defer { if !append { loading = false } }

        do {
            let batch = try await app.api.checkins(
                q: "",
                style: filterStyle,
                minRating: filterRating,
                period: filterPeriod,
                limit: galleryPageSize,
                offset: append ? galleryOffset : 0
            )
            if append {
                items.append(contentsOf: batch)
            } else {
                items = batch
            }
            galleryOffset = items.count
            galleryHasMore = batch.count == galleryPageSize
            if !append {
                app.cache.save(items, name: CacheKey.historyCheckins)
            }
            app.prewarmPhotos(batch)
        } catch let err {
            if !append, let cached = app.cache.load([CheckinItem].self, name: CacheKey.historyCheckins), !cached.isEmpty {
                items = cached
                errorMessage = "Galerie en cache — \(app.networkStatus.label.lowercased())"
            } else if force || items.isEmpty {
                errorMessage = err.localizedDescription
            }
        }
    }
}

private struct GalleryCell: View {
    let item: CheckinItem

    var body: some View {
        ZStack(alignment: .bottom) {
            BeerImage(path: item.photoURL)
                .frame(maxWidth: .infinity)
                .frame(height: 118)
                .clipped()
            Text(item.beerName)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.58))
                .foregroundStyle(.white)
        }
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}