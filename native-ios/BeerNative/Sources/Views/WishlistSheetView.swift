import SwiftUI

struct WishlistSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [WishlistItem] = []
    @State private var name = ""
    @State private var brewery = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Tes souhaits personnels (bières à goûter).")
                        .font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)

                    BeerField(label: "Nom", text: $name, placeholder: "ex. Mama Whipa")
                    BeerField(label: "Brasserie", text: $brewery, placeholder: "optionnel")
                    BeerPrimaryButton(title: "Ajouter", disabled: name.count < 2) {
                        Task { await add() }
                    }

                    if let error { Text(error).foregroundStyle(Theme.error).font(.footnote) }

                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.beerName).font(.headline)
                                Text(item.brewery ?? "—").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button("Goûter") {
                                dismiss()
                                app.startWishlistTaste(item)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                            Button(role: .destructive) { Task { await remove(item) } } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("À boire")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        items = (try? await app.api.wishlist()) ?? []
    }

    private func add() async {
        do {
            try await app.api.addWishlist(beerName: name, brewery: brewery)
            name = ""; brewery = ""
            await load()
        } catch let err { self.error = err.localizedDescription }
    }

    private func remove(_ item: WishlistItem) async {
        try? await app.api.deleteWishlist(id: item.id)
        await load()
    }
}