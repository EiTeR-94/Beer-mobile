import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var items: [CheckinItem] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && items.isEmpty {
                    ProgressView()
                } else if let error, items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash").font(.largeTitle)
                        Text("Historique indisponible")
                        Text(error).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .padding()
                } else if items.isEmpty {
                    VStack(spacing: 8) {
                        Text("🍺").font(.largeTitle)
                        Text("Aucune dégustation")
                        Text("Scanne une bière pour commencer")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding()
                } else {
                    List(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.beerName)
                                .font(.headline)
                            HStack {
                                if let brewery = item.brewery, !brewery.isEmpty {
                                    Text(brewery).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(String(format: "%.2f★", item.rating))
                                    .foregroundStyle(Theme.accent)
                            }
                            .font(.subheadline)
                        }
                        .listRowBackground(Theme.card)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Historique")
            .refreshable { await load() }
            .task { await load() }
            .padding(.top, 40)
        }
    }

    private func load() async {
        guard app.isOnline else {
            error = "Hors ligne — historique nécessite le réseau"
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