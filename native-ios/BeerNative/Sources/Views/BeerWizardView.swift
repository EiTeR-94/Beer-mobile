import PhotosUI
import SwiftUI

struct BeerWizardView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var step: Int

    private var prefill: BeerProduct? { app.wizardProduct }

    @State private var scannedCode = ""
    @State private var manualEAN = ""
    @State private var product: BeerProduct?
    @State private var scanStatus = "Cadre le code-barres dans le rectangle"
    @State private var busy = false

    @State private var untappdBrewery = ""
    @State private var untappdName = ""
    @State private var untappdResults: [UntappdHit] = []
    @State private var untappdError: String?
    @State private var showManual = false
    @State private var manualName = ""
    @State private var manualBrewery = ""
    @State private var styleOptions: [StyleOption] = []
    @State private var manualStyle = ""
    @State private var customStyle = ""

    @State private var scanPhotoItem: PhotosPickerItem?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: UIImage?

    @State private var rating = 3.0
    @State private var comment = ""
    @State private var flavors = Set<String>()
    @State private var hops = Set<String>()
    @State private var customFlavorInput = ""
    @State private var customHopInput = ""
    @State private var flavorTags: [String] = []
    @State private var hopTags: [String] = []
    @State private var showFlavors = true
    @State private var showHops = true
    @State private var saveMessage: String?
    @State private var saving = false
    @State private var showDuplicate = false
    @State private var duplicateDetail = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch step {
                case 1: stepBeer
                case 2: stepPhoto
                default: stepRating
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .onChange(of: photoItem) { item in Task { await loadPhoto(item, tasting: true) } }
        .onChange(of: scanPhotoItem) { item in Task { await decodeScanPhoto(item) } }
        .onAppear {
            applyPrefillIfNeeded()
            Task { styleOptions = (try? await app.api.styles()) ?? [] }
        }
        .onChange(of: app.wizardStep) { applyPrefillIfNeeded() }
        .onChange(of: app.wizardProduct) { _ in applyPrefillIfNeeded() }
        .onChange(of: step) { newStep in
            app.wizardStep = newStep
            if newStep == 3 { Task { await loadNotation() } }
        }
        .alert("Déjà dégustée", isPresented: $showDuplicate) {
            Button("Annuler", role: .cancel) {}
            Button("Noter à nouveau") { Task { await save(force: true) } }
        } message: {
            Text(duplicateDetail.isEmpty
                 ? "Ajouter cette nouvelle note à ton historique ?"
                 : duplicateDetail)
        }
    }

    // MARK: - Step 1

    private var stepBeer: some View {
        Group {
            BeerLead(text: "Scan EAN optionnel — ou cherche directement sur Untappd.")

            ZStack(alignment: .bottom) {
                BarcodeScannerView { code in
                    scannedCode = code
                    manualEAN = code
                    Task { await lookupEAN(code) }
                }
                .frame(height: min(UIScreen.main.bounds.width * 0.75, 320))
                .background(Theme.photoBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    ScanViewfinderOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))

                Text(scanStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(12)
            }

            PhotosPicker(selection: $scanPhotoItem, matching: .images) {
                Text("📷 Prendre photo du code-barres")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }

            DisclosureGroup("Code illisible ? Saisie EAN à la main", isExpanded: .constant(true)) {
                HStack {
                    TextField("ex. 5411680001111", text: $manualEAN)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.text)
                    Button("Identifier par EAN") { Task { await lookupEAN(manualEAN) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .tint(Theme.accent)

            VStack(alignment: .leading, spacing: 10) {
                Text("Chercher sur Untappd")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Top 5 résultats — utilise Brasserie + Nom pour affiner.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                BeerField(label: "Brasserie (optionnel)", text: $untappdBrewery, placeholder: "ex. Les Intenables")
                BeerField(label: "Nom de la bière", text: $untappdName, placeholder: "ex. Mama Whipa")
                BeerPrimaryButton(title: busy ? "Recherche…" : "Chercher sur Untappd", disabled: untappdName.count < 2 && untappdBrewery.count < 2, busy: busy) {
                    Task { await searchUntappd() }
                }

                if let untappdError {
                    Text(untappdError).font(.footnote).foregroundStyle(Theme.muted)
                }
                ForEach(untappdResults) { hit in
                    Button { Task { await selectUntappd(hit) } } label: {
                        HStack(spacing: 10) {
                            BeerImage(path: hit.photoURL)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.beerName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text([hit.brewery, hit.styleFr].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .padding(10)
                        .background(Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .beerCard()

            DisclosureGroup("Saisie manuelle (secours)", isExpanded: $showManual) {
                BeerField(label: "Nom de la bière", text: $manualName, placeholder: "ex. Mama Whipa")
                BeerField(label: "Brasserie", text: $manualBrewery, placeholder: "ex. Les Intenables")
                Picker("Style", selection: $manualStyle) {
                    Text("Choisir…").tag("")
                    ForEach(styleOptions.filter { !$0.value.isEmpty }) { s in
                        Text(s.label).tag(s.value)
                    }
                    Text("Autre (saisir manuellement)").tag("__other__")
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                if manualStyle == "__other__" {
                    BeerField(label: "Style personnalisé", text: $customStyle, placeholder: "ex. IPA")
                }
                BeerPrimaryButton(title: "Continuer", disabled: manualName.count < 2) {
                    Task { await saveManualProduct() }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .tint(Theme.accent)

            if let product, !product.beerName.isEmpty {
                BeerPreviewCard(product: product)
                BeerSecondaryButton(title: "Changer de bière") { clearProduct() }
                if !app.isInvite {
                    BeerSecondaryButton(title: "+ Ajouter à la liste « À boire »") {
                        Task { await addToWishlist(product) }
                    }
                }
                BeerPrimaryButton(title: "Continuer → photo") { step = 2 }
            }
        }
    }

    // MARK: - Step 2

    private var stepPhoto: some View {
        Group {
            BeerLead(text: "Photo du verre avec la canette à côté (optionnel).")

            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.border, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Theme.card)
                        .frame(minHeight: 180)
                    if let photoPreview {
                        Image(uiImage: photoPreview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(8)
                    } else {
                        Text("📷 Prendre ou choisir une photo")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            BeerSecondaryButton(title: "← Retour") { step = 1 }
            BeerPrimaryButton(title: "Continuer → note") {
                step = 3
                Task { await loadNotation() }
            }
        }
    }

    // MARK: - Step 3

    private var stepRating: some View {
        Group {
            if let product {
                Text(product.beerName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !product.displayStyle.isEmpty && product.displayStyle != "Unknown" {
                    Text("(\(product.displayStyle))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                BeerLead(text: "Pas de bière identifiée — retourne à l'étape 1.")
            }

            UntappdRatingSlider(rating: $rating)
                .padding(.vertical, 8)

            if showFlavors {
                if !flavorTags.isEmpty {
                    FlavorTagGrid(title: "Goûts", tags: flavorTags, selected: $flavors, maxCount: 8)
                }
                CustomTagInput(placeholder: "Goût perso", input: $customFlavorInput, selected: $flavors, maxCount: 8)
                CustomTagChips(selected: $flavors, customOnly: flavors.subtracting(Set(flavorTags)))
            }
            if showHops {
                if !hopTags.isEmpty {
                    FlavorTagGrid(title: "Houblons", tags: hopTags, selected: $hops, maxCount: 6)
                }
                CustomTagInput(
                    placeholder: "Houblon perso",
                    input: $customHopInput,
                    selected: $hops,
                    maxCount: 6,
                    registerOnServer: { try await app.api.addHop($0) }
                )
                CustomTagChips(selected: $hops, customOnly: hops.subtracting(Set(hopTags)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Commentaire (optionnel, 120 car.)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                TextField("Terrasse, avec elle, à refaire…", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: comment) { v in
                        if v.count > 120 { comment = String(v.prefix(120)) }
                    }
                    .padding(12)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Theme.text)
                Text("\(comment.count)/120")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote)
                    .foregroundStyle(saveMessage.contains("✓") ? Theme.ok : Theme.accent)
                    .multilineTextAlignment(.center)
            }

            BeerSecondaryButton(title: "← Retour") { step = 2 }
            BeerPrimaryButton(
                title: saving ? "Enregistrement…" : "Enregistrer",
                disabled: product == nil || rating < 0.25,
                busy: saving
            ) {
                Task { await save(force: false) }
            }
        }
    }

    // MARK: - Actions

    private func lookupEAN(_ code: String) async {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 8 else {
            scanStatus = "Code trop court"
            return
        }
        busy = true
        scanStatus = "Recherche…"
        defer { busy = false }

        if !app.isOnline {
            scannedCode = digits
            scanStatus = "Hors ligne — saisie manuelle ou Untappd"
            return
        }

        do {
            let res = try await app.api.lookup(barcode: digits)
            if res.ok {
                product = res.asProduct(fallbackBarcode: digits)
                scanStatus = "Bière identifiée ✓"
            } else {
                product = nil
                scannedCode = digits
                scanStatus = res.error ?? "Introuvable"
            }
        } catch let err {
            scanStatus = err.localizedDescription
        }
    }

    private func decodeScanPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let raw = try? await item.loadTransferable(type: Data.self) else { return }
        let jpeg = BeerImageUtils.compressJPEG(raw)
        busy = true
        scanStatus = "Décodage photo…"
        defer { busy = false }
        do {
            let scan = try await app.api.scanPhoto(jpeg: jpeg)
            if scan.ok {
                let digits = scan.barcode ?? ""
                scannedCode = digits
                manualEAN = digits
                product = scan.asProduct(fallbackBarcode: digits)
                scanStatus = "Bière identifiée ✓"
            } else {
                scanStatus = scan.error ?? "Code illisible"
            }
        } catch let err {
            scanStatus = err.localizedDescription
        }
    }

    private func saveManualProduct() async {
        let style = manualStyle == "__other__" ? (customStyle.isEmpty ? "Unknown" : customStyle) : (manualStyle.isEmpty ? "Unknown" : manualStyle)
        let digits = manualEAN.filter(\.isNumber)
        busy = true
        defer { busy = false }
        if digits.count >= 8, app.isOnline {
            do {
                let res = try await app.api.saveProduct(
                    barcode: digits,
                    beerName: manualName,
                    brewery: manualBrewery.isEmpty ? "—" : manualBrewery,
                    style: style
                )
                product = res.asProduct(fallbackBarcode: digits)
                scannedCode = digits
                step = 2
                return
            } catch {
                // fallback local
            }
        }
        product = BeerProduct(
            barcode: digits,
            beerName: manualName,
            brewery: manualBrewery.isEmpty ? "—" : manualBrewery,
            style: style
        )
        step = 2
    }

    private func searchUntappd() async {
        let q = [untappdBrewery, untappdName].filter { !$0.isEmpty }.joined(separator: " ")
        guard q.count >= 2 else { return }
        busy = true
        untappdError = nil
        defer { busy = false }
        do {
            let res = try await app.api.untappdSearch(query: q)
            if res.ok, let hits = res.results, !hits.isEmpty {
                untappdResults = hits
            } else {
                untappdResults = []
                untappdError = res.error ?? "Aucun résultat"
            }
        } catch let err {
            untappdResults = []
            untappdError = err.localizedDescription
        }
    }

    private func selectUntappd(_ hit: UntappdHit) async {
        busy = true
        defer { busy = false }
        let ean = scannedCode.filter(\.isNumber)
        do {
            let res: LookupResponse
            if ean.count >= 8 {
                res = try await app.api.linkProduct(
                    bid: hit.bid,
                    barcode: ean,
                    beerName: hit.beerName,
                    brewery: hit.brewery ?? ""
                )
            } else {
                res = try await app.api.untappdFetch(
                    bid: hit.bid,
                    barcode: scannedCode,
                    beerName: hit.beerName,
                    brewery: hit.brewery ?? ""
                )
            }
            if res.ok {
                product = res.asProduct(fallbackBarcode: ean.isEmpty ? scannedCode : ean)
                scanStatus = "Untappd ✓"
                untappdResults = []
            } else {
                untappdError = res.error ?? "Fiche introuvable"
            }
        } catch let err {
            untappdError = err.localizedDescription
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?, tasting: Bool) async {
        guard let item else { return }
        if let raw = try? await item.loadTransferable(type: Data.self) {
            let jpeg = BeerImageUtils.compressJPEG(raw)
            photoData = jpeg
            photoPreview = UIImage(data: jpeg)
        }
    }

    private func loadNotation() async {
        guard let product, app.isOnline else { return }
        do {
            let n = try await app.api.flavors(style: product.style, description: product.summary)
            flavorTags = n.flavors ?? []
            hopTags = n.hops ?? []
            showFlavors = n.showFlavorsBlock ?? true
            showHops = n.showHopsBlock ?? true
            flavors = Set(n.suggestedFlavors ?? [])
            hops = Set(n.suggestedHops ?? [])
        } catch {
            flavorTags = []
            hopTags = []
        }
    }

    private func save(force: Bool) async {
        guard let product else { return }
        saving = true
        saveMessage = nil
        defer { saving = false }
        do {
            let msg = try await app.saveCheckin(
                product: product,
                rating: rating,
                flavors: Array(flavors),
                hops: Array(hops),
                comment: comment,
                photoJPEG: photoData,
                force: force
            )
            if msg.hasPrefix("duplicate|") {
                let parts = msg.split(separator: "|").map(String.init)
                if parts.count >= 4 {
                    duplicateDetail = "\(parts[1]) — \(BeerFormatters.ratingLabel(Double(parts[2]) ?? 0)) ★ · \(BeerFormatters.formatDate(parts[3]))\n\nAjouter cette nouvelle note à ton historique ?"
                }
                showDuplicate = true
                return
            }
            saveMessage = msg
            try? await Task.sleep(nanoseconds: 900_000_000)
            resetWizard()
        } catch let err {
            saveMessage = err.localizedDescription
        }
    }

    private func applyPrefillIfNeeded() {
        if app.wizardStep != step { step = app.wizardStep }
        guard let p = prefill, !p.beerName.isEmpty else { return }
        product = p
        if step == 3 { Task { await loadNotation() } }
    }

    private func clearProduct() {
        product = nil
        untappdResults = []
        scanStatus = "Cadre le code-barres dans le rectangle"
    }

    private func addToWishlist(_ product: BeerProduct) async {
        do {
            try await app.api.addWishlist(
                beerName: product.beerName,
                brewery: product.brewery,
                style: product.style,
                barcode: product.barcode
            )
            scanStatus = "Ajouté à « À boire » ✓"
        } catch let err {
            scanStatus = err.localizedDescription
        }
    }

    private func resetWizard() {
        app.clearWizardPrefill()
        step = 1
        product = nil
        scannedCode = ""
        manualEAN = ""
        untappdBrewery = ""
        untappdName = ""
        untappdResults = []
        manualName = ""
        manualBrewery = ""
        manualStyle = ""
        customStyle = ""
        photoItem = nil
        scanPhotoItem = nil
        photoData = nil
        photoPreview = nil
        rating = 3.0
        comment = ""
        flavors = []
        hops = []
        customFlavorInput = ""
        customHopInput = ""
        scanStatus = "Cadre le code-barres dans le rectangle"
        saveMessage = nil
        duplicateDetail = ""
    }
}