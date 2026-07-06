import SwiftUI

struct GallerySheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CheckinItem] = []
    @State private var search = ""
    @State private var selected: CheckinItem?

    private var withPhotos: [CheckinItem] {
        items.filter { ($0.photoURL?.isEmpty == false) }
            .filter { item in
                guard !search.isEmpty else { return true }
                let hay = "\(item.beerName) \(item.brewery ?? "") \(item.style ?? "")".lowercased()
                return hay.contains(search.lowercased())
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding(12)
                if withPhotos.isEmpty {
                    Text("Aucune photo").foregroundStyle(Theme.muted).padding()
                }
            }
            .background(Theme.bg)
            .navigationTitle("Galerie photos")
            .searchable(text: $search, prompt: "nom, brasserie…")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task {
                items = (try? await app.api.checkins(limit: 50, offset: 0)) ?? []
            }
            .sheet(item: $selected) { item in
                CheckinDetailView(item: item, onRetaste: {
                    selected = nil; dismiss(); app.startRetaste(item)
                }, onEdit: { selected = nil })
            }
        }
        .preferredColorScheme(.dark)
    }
}