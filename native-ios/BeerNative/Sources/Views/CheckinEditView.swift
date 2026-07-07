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
        BeerOverlayScreen(title: "Modifier la dégustation", onClose: { dismiss() }) {
            VStack(spacing: 14) {
                Text("\(item.brewery ?? "—") · \(item.style ?? "?") · \(BeerFormatters.formatDate(item.createdAt))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.border, style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .background(Theme.card)
                            .frame(minHeight: 140)
                        if let path = item.photoURL, !removePhoto, newPhoto == nil {
                            BeerImage(path: path)
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .padding(8)
                        } else {
                            Text("📷 Prendre ou choisir une photo")
                                .font(.system(size: Theme.Font.lead))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                if item.photoURL != nil {
                    BeerSecondaryButton(title: "Retirer la photo") { removePhoto = true; newPhoto = nil }
                }

                UntappdRatingSlider(rating: $rating)

                if !flavorTags.isEmpty {
                    FlavorTagGrid(title: "Goûts", tags: flavorTags, selected: $flavors, maxCount: 8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goûts perso")
                        .font(.system(size: Theme.Font.tagTitle))
                        .foregroundStyle(Theme.muted)
                    CustomTagInput(
                        placeholder: "ex. pneus, sucrée…",
                        input: $customFlavorInput,
                        selected: $flavors,
                        maxCount: 8
                    )
                    CustomTagChips(selected: $flavors, customOnly: flavors.subtracting(Set(flavorTags)))
                }

                if !hopTags.isEmpty {
                    FlavorTagGrid(title: "Houblons", tags: hopTags, selected: $hops, maxCount: 6)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Houblons perso")
                        .font(.system(size: Theme.Font.tagTitle))
                        .foregroundStyle(Theme.muted)
                    CustomTagInput(
                        placeholder: "ex. Citra, Mosaic…",
                        input: $customHopInput,
                        selected: $hops,
                        maxCount: 6,
                        onRegister: { name in Task { try? await app.api.addHop(name) } }
                    )
                    CustomTagChips(selected: $hops, customOnly: hops.subtracting(Set(hopTags)))
                }

                if app.isAdmin {
                    Toggle("Masquer cette dégustation pour les autres", isOn: $hidden)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .tint(Theme.accent)
                }

                BeerField(label: "Commentaire", text: $comment)

                if let message {
                    Text(message).font(.footnote).foregroundStyle(Theme.error)
                }

                BeerSecondaryButton(title: "Annuler") { dismiss() }
                BeerPrimaryButton(title: busy ? "Enregistrement…" : "Enregistrer", busy: busy) {
                    Task { await save() }
                }
            }
        }
        .onChange(of: photoItem, perform: { p in Task { await loadPhoto(p) } })
        .task { await loadTags() }
    }

    private func loadTags() async {
        if let n = try? await app.api.flavors(style: item.style ?? "Unknown", description: "") {
            flavorTags = n.flavors ?? []
            hopTags = n.hops ?? []
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let raw = try? await item.loadTransferable(type: Data.self) {
            newPhoto = BeerImageUtils.compressJPEG(raw)
            removePhoto = false
        }
    }

    private func save() async {
        busy = true
        message = nil
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