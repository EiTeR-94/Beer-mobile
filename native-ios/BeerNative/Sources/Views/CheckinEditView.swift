import PhotosUI
import SwiftUI

struct CheckinEditView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: CheckinItem
    let onSaved: () -> Void

    @State private var rating: Double
    @State private var comment: String
    @State private var flavors = Set<String>()
    @State private var hops = Set<String>()
    @State private var flavorTags: [String] = []
    @State private var hopTags: [String] = []
    @State private var hidden = false
    @State private var photoItem: PhotosPickerItem?
    @State private var newPhoto: Data?
    @State private var removePhoto = false
    @State private var busy = false
    @State private var message: String?

    init(item: CheckinItem, onSaved: @escaping () -> Void) {
        self.item = item
        self.onSaved = onSaved
        _rating = State(initialValue: item.rating)
        _comment = State(initialValue: item.comment ?? "")
        _flavors = State(initialValue: Set(item.flavors ?? []))
        _hops = State(initialValue: Set(item.hops ?? []))
        _hidden = State(initialValue: item.hiddenFromPartner == true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(item.beerName).font(.headline)
                    BeerImage(path: item.photoURL)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    PhotosPicker("Changer la photo", selection: $photoItem, matching: .images)
                        .foregroundStyle(Theme.accent)
                    if item.photoURL != nil {
                        Button("Retirer la photo", role: .destructive) { removePhoto = true; newPhoto = nil }
                            .font(.caption)
                    }
                    UntappdRatingSlider(rating: $rating)
                    if !flavorTags.isEmpty {
                        FlavorTagGrid(title: "Goûts", tags: flavorTags, selected: $flavors, maxCount: 8)
                    }
                    if !hopTags.isEmpty {
                        FlavorTagGrid(title: "Houblons", tags: hopTags, selected: $hops, maxCount: 6)
                    }
                    BeerField(label: "Commentaire", text: $comment)
                    if app.isAdmin {
                        Toggle("Masquer pour les autres", isOn: $hidden).tint(Theme.accent)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.error) }
                    BeerPrimaryButton(title: busy ? "Enregistrement…" : "Enregistrer", busy: busy) {
                        Task { await save() }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Modifier")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .task { await loadTags() }
            .onChange(of: photoItem) { p in Task { newPhoto = try? await p?.loadTransferable(type: Data.self); removePhoto = false } }
        }
        .preferredColorScheme(.dark)
    }

    private func loadTags() async {
        if let n = try? await app.api.flavors(style: item.style ?? "Unknown") {
            flavorTags = n.flavors ?? []
            hopTags = n.hops ?? []
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.updateCheckin(
                id: item.id,
                rating: rating,
                flavors: Array(flavors),
                hops: Array(hops),
                comment: String(comment.prefix(120)),
                hiddenFromPartner: app.isAdmin ? hidden : nil
            )
            if removePhoto { try await app.api.removeCheckinPhoto(id: item.id) }
            else if let newPhoto { try await app.api.replaceCheckinPhoto(id: item.id, jpeg: newPhoto) }
            onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}