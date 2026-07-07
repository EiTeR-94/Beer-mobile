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
    @State private var errorMessage: String?
    @State private var reloadTask: Task<Void, Never>?

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
                BeerHistorySearchField(text: $search)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.error)
                }

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
        .onChange(of: search, perform: { _ in scheduleReload() })
        .onChange(of: filterStyle, perform: { _ in scheduleReload() })
        .onChange(of: filterRating, perform: { _ in scheduleReload() })
        .onChange(of: filterPeriod, perform: { _ in scheduleReload() })
        .task { await bootstrap() }
        .onDisappear { reloadTask?.cancel() }
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
            CheckinEditView(item: item) { scheduleReload() }
                .beerSheetChrome()
        }
    }

    private func bootstrap() async {
        styles = (try? await app.api.styles()) ?? []
        await reload(force: true)
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { await reload(force: false) }
    }

    private func reload(force: Bool) async {
        if loading, !force { return }
        loading = true
        errorMessage = nil
        defer { loading = false }

        var all: [CheckinItem] = []
        var failed = false
        for off in stride(from: 0, to: 150, by: 50) {
            if Task.isCancelled { return }
            do {
                let batch = try await app.api.checkins(
                    q: search.trimmingCharacters(in: .whitespaces),
                    style: filterStyle,
                    minRating: filterRating,
                    period: filterPeriod,
                    limit: 50,
                    offset: off
                )
                all.append(contentsOf: batch)
                if batch.count < 50 { break }
            } catch let err {
                failed = true
                if force || items.isEmpty {
                    errorMessage = err.localizedDescription
                }
                break
            }
        }

        if Task.isCancelled { return }
        if !all.isEmpty || !failed {
            items = all
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