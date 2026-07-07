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
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(withPhotos) { item in
                            Button { selected = item } label: {
                                GalleryCell(item: item)
                            }
                            .buttonStyle(.plain)
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

        var all: [CheckinItem] = []
        var failed = false
        var offset = 0
        let pageSize = 50
        let maxFetch = 1000 // safety cap

        while offset < maxFetch {
            do {
                let batch = try await app.api.checkins(
                    q: "",
                    style: filterStyle,
                    minRating: filterRating,
                    period: filterPeriod,
                    limit: pageSize,
                    offset: offset
                )
                all.append(contentsOf: batch)
                if batch.count < pageSize { break }
                offset += pageSize
            } catch let err {
                failed = true
                if let cached = app.cache.load([CheckinItem].self, name: CacheKey.historyCheckins), !cached.isEmpty {
                    items = cached
                    errorMessage = "Galerie en cache — \(app.networkStatus.label.lowercased())"
                    return
                }
                if force || items.isEmpty {
                    errorMessage = err.localizedDescription
                }
                return
            }
        }

        if !all.isEmpty || !failed {
            items = all
            app.cache.save(all, name: CacheKey.historyCheckins)
            errorMessage = nil
            app.prewarmPhotos(all)
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