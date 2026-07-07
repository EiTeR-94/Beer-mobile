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
    }

    var body: some View {
        BeerOverlayScreen(title: "Galerie photos", onClose: { dismiss() }) {
            VStack(spacing: 10) {
                BeerHistoryFiltersRow(
                    filterStyle: $filterStyle,
                    filterRating: $filterRating,
                    filterPeriod: $filterPeriod,
                    styles: styles
                )
                BeerHistorySearchField(text: $search)

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
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(withPhotos) { item in
                            Button { selected = item } label: {
                                BeerImage(path: item.photoURL)
                                    .frame(minHeight: 110)
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .bottom) {
                                        Text(item.beerName)
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .padding(4)
                                            .frame(maxWidth: .infinity)
                                            .background(.black.opacity(0.55))
                                            .foregroundStyle(.white)
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: search, perform: { _ in Task { await reload() } })
        .onChange(of: filterStyle, perform: { _ in Task { await reload() } })
        .onChange(of: filterRating, perform: { _ in Task { await reload() } })
        .onChange(of: filterPeriod, perform: { _ in Task { await reload() } })
        .task { await bootstrap() }
        .refreshable { await reload() }
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
        }
        .sheet(item: $editing) { item in
            CheckinEditView(item: item) { Task { await reload() } }
                .beerSheetChrome()
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
        for off in stride(from: 0, to: 150, by: 50) {
            let batch = (try? await app.api.checkins(
                q: search.trimmingCharacters(in: .whitespaces),
                style: filterStyle,
                minRating: filterRating,
                period: filterPeriod,
                limit: 50,
                offset: off
            )) ?? []
            all.append(contentsOf: batch)
            if batch.count < 50 { break }
        }
        items = all
    }
}