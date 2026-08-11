import PhotosUI
import SwiftUI

struct CheckinEditView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let item: CheckinItem
    let onSaved: () -> Void

    @State private var rating: Double
    @State private var comment: String
    @State private var location: String
    @State private var locationLat: Double?
    @State private var locationLon: Double?
    @State private var locationOsmId: String?
    @State private var locationResults: [GeocodeHit] = []
    @State private var locationSearchTask: Task<Void, Never>?
    @State private var suppressLocationChange = false
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
        _location = State(initialValue: item.location ?? "")
        _locationLat = State(initialValue: item.locationLat)
        _locationLon = State(initialValue: item.locationLon)
        _locationOsmId = State(initialValue: item.locationOsmId)
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

                BeerField(
                    label: "Lieu ou lien",
                    text: $location,
                    placeholder: "ex. Chez nous · https://maps.app.goo.gl/…"
                )
                .onChange(of: location) { _ in
                    if suppressLocationChange {
                        suppressLocationChange = false
                        return
                    }
                    locationLat = nil
                    locationLon = nil
                    locationOsmId = nil
                    LocationBiasProvider.shared.requestOnce()
                    scheduleLocationSearch()
                }
                if locationLat != nil {
                    Text("✓ Lieu vérifié (OpenStreetMap)")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
                ForEach(locationResults) { hit in
                    Button {
                        pickLocation(hit)
                    } label: {
                        HStack(spacing: 6) {
                            Text("📍").font(.caption)
                            Text(hit.label).font(.caption).foregroundStyle(Theme.text)
                            Spacer()
                        }
                        .padding(8)
                        .background(Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

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
        .task { LocationBiasProvider.shared.requestOnce() }
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

    /// Recherche de lieu (OSM/Photon) débouncée — annule la recherche en cours à chaque frappe.
    private func scheduleLocationSearch() {
        locationSearchTask?.cancel()
        let query = location
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            locationResults = []
            return
        }
        locationSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let bias = LocationBiasProvider.shared.coordinate
            do {
                let res = try await app.api.geocodeSearch(query: query, lat: bias?.latitude, lon: bias?.longitude)
                guard !Task.isCancelled else { return }
                locationResults = res.results ?? []
            } catch {
                guard !Task.isCancelled else { return }
                locationResults = []
            }
        }
    }

    private func pickLocation(_ hit: GeocodeHit) {
        suppressLocationChange = true
        location = String(hit.label.prefix(300))
        locationLat = hit.lat
        locationLon = hit.lon
        locationOsmId = hit.osmId
        locationResults = []
        locationSearchTask?.cancel()
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
                hiddenFromPartner: app.isAdmin ? hidden : nil,
                location: String(location.prefix(300)),
                locationLat: locationLat,
                locationLon: locationLon,
                locationOsmId: locationOsmId
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