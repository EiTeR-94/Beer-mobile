import SwiftUI

struct CheckinFormView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let product: BeerProduct
    let onDone: () -> Void

    @State private var rating = 3.0
    @State private var comment = ""
    @State private var message: String?
    @State private var busy = false
    @State private var showDuplicate = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.beerName)
                        .font(.title2.bold())
                    Text(product.brewery)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    Text(String(format: "%.2f / 5", rating))
                        .font(.title.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Slider(value: $rating, in: 0.25...5, step: 0.25)
                }
                .beerCard()

                TextField("Commentaire (optionnel)", text: $comment, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.contains("✓") ? .green : Theme.accent)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await save(force: false) }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.black) }
                        Text(busy ? "Enregistrement…" : "Enregistrer")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(busy || rating < 0.25)

                Spacer()
            }
            .padding(20)
            .background(Theme.bg)
            .navigationTitle("Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Déjà dégustée", isPresented: $showDuplicate) {
                Button("Annuler", role: .cancel) {}
                Button("Ajouter quand même") { Task { await save(force: true) } }
            } message: {
                Text("Cette bière est déjà dans ton historique. Confirmer une nouvelle dégustation ?")
            }
        }
    }

    private func save(force: Bool) async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            let msg = try await app.saveCheckin(product: product, rating: rating, comment: comment, force: force)
            if msg == "duplicate" {
                showDuplicate = true
                return
            }
            message = msg
            try? await Task.sleep(nanoseconds: 900_000_000)
            onDone()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}