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
    @State private var customFlavorInput = ""
    @State private var customHopInput = ""
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
                    Text("\(item.brewery ?? "—") · \(item.style ?? "?") · \(BeerFormatters.formatDate(item.createdAt))")
                        .font(.caption).foregroundStyle(Theme.muted)
                    BeerImage(path: item.photoURL)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    PhotosPicker("📷 Prendre ou choisir une photo", selection: $photoItem, matching: .images)
                        .foregroundStyle(Theme.accent)
                    if item.photoURL != nil {
                        Button("Retirer la photo", role: .destructive) { removePhoto = true; newPhoto = nil }
                            .font(.caption)
                    }
                    UntappdRatingSlider(rating: $rating)
                    if !flavorTags.isEmpty {
                        FlavorTagGrid(title: "Goûts", tags: flavorTags, selected: $flavors, maxCount: 8)
                    }
                    CustomTagInput(placeholder: "Goût perso", input: $customFlavorInput, selected: $flavors, maxCount: 8)
                    CustomTagChips(selected: $flavors, customOnly: flavors.subtracting(Set(flavorTags)))
                    if !hopTags.isEmpty {
                        FlavorTagGrid(title: "Houblons", tags: hopTags, selected: $hops, maxCount: 6)
                    }
                    CustomTagInput(
                        placeholder: "Houblon perso",
                        input: $customHopInput,
                        selected: $hops,
                        maxCount: 6,
                        onRegister: { name in Task { try? await app.api.addHop(name) } }
                    )
                    CustomTagChips(selected: $hops, customOnly: hops.subtracting(Set(hopTags)))
                    BeerField(label: "Commentaire (120 car.)", text: $comment)
                    if app.isAdmin {
                        Toggle("Masquer cette dégustation pour les autres", isOn: $hidden).tint(Theme.accent)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.error) }
                    BeerPrimaryButton(title: busy ? "Enregistrement…" : "Enregistrer", busy: busy) {
                        Task { await save() }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Modifier la dégustation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
            .task { await loadTags() }
            .onChange(of: photoItem) { p in
                Task {
                    if let raw = try? await p?.loadTransferable(type: Data.self) {
                        newPhoto = BeerImageUtils.compressJPEG(raw)
                        removePhoto = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadTags() async {
        if let n = try? await app.api.flavors(style: item.style ?? "Unknown", description: "") {
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
        } catch let err {
            message = err.localizedDescription
        }
    }
}