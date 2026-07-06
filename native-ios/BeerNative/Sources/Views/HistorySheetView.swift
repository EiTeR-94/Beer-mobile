import SwiftUI

struct HistorySheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CheckinItem] = []
    @State private var error: String?
    @State private var loading = false
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if loading && items.isEmpty {
                    ProgressView().tint(Theme.accent)
                } else if let error, items.isEmpty {
                    VStack(spacing: 8) {
                        Text("Historique indisponible")
                        Text(error).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .padding()
                } else if filtered.isEmpty {
                    Text("Aucune dégustation")
                        .foregroundStyle(Theme.muted)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { item in
                                HistoryCardView(item: item, photoBase: app.api.baseURL)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .searchable(text: $search, prompt: "nom, brasserie, style…")
            .refreshable { await load() }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private var filtered: [CheckinItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.beerName.lowercased().contains(q)
                || ($0.brewery?.lowercased().contains(q) ?? false)
                || ($0.style?.lowercased().contains(q) ?? false)
        }
    }

    private func load() async {
        guard app.isOnline else {
            error = "Hors ligne"
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            items = try await app.api.checkins(limit: 50)
        } catch {
            self.error = error.localizedDescription
        }
    }
}