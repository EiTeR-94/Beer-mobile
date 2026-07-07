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
    @State private var showEANManual = false
    @State private var manualName = ""
    @State private var manualBrewery = ""
    @State private var styleOptions: [StyleOption] = []
    @State private var manualStyle = ""
    @State private var customStyle = ""

    @State private var showScanCamera = false
    @State private var showTastingCamera = false
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
    @State private var saving = false
    @State private var showDuplicate = false
    @State private var duplicateDetail = ""

    private var manualStyleOptions: [(String, String)] {
        var opts: [(String, String)] = [("", "Choisir…")]
        opts.append(contentsOf: styleOptions.filter { !$0.value.isEmpty }.map { ($0.value, $0.label) })
        opts.append(("__other__", "Autre (saisir manuellement)"))
        return opts
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Group {
                    switch step {
                    case 1: stepBeer
                    case 2: stepPhoto
                    default: stepRating
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.25), value: step)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .fullScreenCover(isPresented: $showScanCamera) {
            CameraPicker { image in Task { await processScanPhoto(image) } }
        }
        .fullScreenCover(isPresented: $showTastingCamera) {
            CameraPicker { image in Task { await processTastingPhoto(image) } }
        }
        .onAppear {
            applyPrefillIfNeeded()
            Task { styleOptions = (try? await app.api.styles()) ?? [] }
        }
        .onChange(of: app.wizardStep, perform: { _ in applyPrefillIfNeeded() })
        .onChange(of: app.wizardProduct, perform: { _ in applyPrefillIfNeeded() })
        .onChange(of: step, perform: { newStep in
            app.wizardStep = newStep
            if newStep == 3 { Task { await loadNotation() } }
        })
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

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    BarcodeScannerView { code in
                        scannedCode = code
                        manualEAN = code
                        app.showToast(
                            "Code-barres lu ✓",
                            variant: .success,
                            detail: code,
                            label: "Scan",
                            durationMs: 2400
                        )
                        Task { await lookupEAN(code) }
                    }
                    .frame(height: min(min((UIScreen.main.bounds.width - 32) * 0.75, UIScreen.main.bounds.height * 0.48), 320))
                    .background(Theme.photoBg)
                    .overlay {
                        ScanViewfinderOverlay()
                    }

                    Button { showScanCamera = true } label: {
                        Text("Prendre photo")
                            .font(.system(size: Theme.Font.ghost, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.card.opacity(0.92))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
                    }
                    .padding(.bottom, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
                .background(Theme.card)
            }

            Text(scanStatus)
                .font(.system(size: Theme.Font.lead * 0.94))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                Text("Chercher sur Untappd")
                    .font(.system(size: Theme.Font.tagTitle, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Top 5 résultats seulement (limite Untappd dans le HTML). Utilise Brasserie + Nom pour faire apparaître ta bière précise dans ces 5.")
                    .font(.system(size: Theme.Font.lead * 0.94))
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
                            // Use AsyncImage for external Untappd labels to guarantee loading (bypasses custom homelab download path that had pinning/transport issues)
                            if let urlStr = hit.photoURL, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 8).fill(Theme.card).overlay(Text("🍺").font(.caption2))
                                    default:
                                        RoundedRectangle(cornerRadius: 8).fill(Theme.card).overlay(ProgressView().scaleEffect(0.6))
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Photo de la bière depuis Untappd")
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.card)
                                    .frame(width: 44, height: 44)
                                    .overlay(Text("🍺").font(.caption2).foregroundStyle(Theme.muted))
                            }
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

                DisclosureGroup("Saisie manuelle (secours)", isExpanded: $showManual) {
                    BeerField(label: "Nom de la bière", text: $manualName, placeholder: "ex. Mama Whipa")
                    BeerField(label: "Brasserie", text: $manualBrewery, placeholder: "ex. Les Intenables")
                    BeerFormSelectField(
                        label: "Style",
                        value: manualStyle,
                        options: manualStyleOptions,
                        onSelect: { manualStyle = $0 }
                    )
                    .padding(.top, 10)
                    if manualStyle == "__other__" {
                        BeerField(label: "Style", text: $customStyle, placeholder: "Ex: Gose, Table Beer, etc.")
                    }
                    BeerSecondaryButton(title: "Continuer") {
                        Task { await saveManualProduct() }
                    }
                }
                .font(.system(size: Theme.Font.field))
                .foregroundStyle(Theme.muted)
                .tint(Theme.accent)
            }
            .beerCard()

            DisclosureGroup("Code illisible ? Saisie EAN à la main", isExpanded: $showEANManual) {
                BeerField(label: "Code EAN", text: $manualEAN, placeholder: "ex. 5411680001111", keyboard: .numberPad)
                BeerSecondaryButton(title: "Identifier par EAN") {
                    Task { await lookupEAN(manualEAN) }
                }
            }
            .font(.system(size: Theme.Font.field))
            .foregroundStyle(Theme.muted)
            .tint(Theme.accent)

            if let product, !product.beerName.isEmpty {
                BeerPreviewCard(product: product)
                // Invités 5G : full features (même que web), via chemin standard domaine.
                BeerSecondaryButton(title: "+ Ajouter à la liste « À boire »") {
                    Task { await addToWishlist(product) }
                }
                BeerPrimaryButton(title: "Continuer → photo") { step = 2 }
            }
        }
    }

    // MARK: - Step 2

    private var stepPhoto: some View {
        Group {
            BeerLead(text: "Photo du verre avec la canette à côté (optionnel).")

            Button { showTastingCamera = true } label: {
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
                        Text("📷 Prendre une photo")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)

            BeerSecondaryButton(title: "← Retour") { step = 1 }
            BeerPrimaryButton(title: "Continuer → note") {
                step = 3
                Task { await loadNotation() }
            }
        }
    }

    private var flavorTagsTitle: String {
        guard let product,
              !product.displayStyle.isEmpty,
              product.displayStyle != "Unknown" else { return "Goûts" }
        return "Goûts \(product.displayStyle)"
    }

    // MARK: - Step 3

    private var stepRating: some View {
        Group {
            if let product, !product.beerName.isEmpty {
                BeerLead(text: product.beerName)
            } else {
                BeerLead(text: "Pas de bière identifiée — retourne à l'étape 1 ou cherche sur Untappd.")
            }

            VStack(alignment: .leading, spacing: 10) {
                UntappdRatingSlider(rating: $rating)
            }
            .beerCard()

            if showFlavors {
                if !flavorTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        FlavorTagGrid(title: flavorTagsTitle, tags: flavorTags, selected: $flavors, maxCount: 8)
                    }
                    .beerCard()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goûts perso")
                        .font(.system(size: Theme.Font.tagTitle, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    CustomTagInput(
                        placeholder: "ex. pneus, sucrée, vanille fumée…",
                        input: $customFlavorInput,
                        selected: $flavors,
                        maxCount: 8
                    )
                    CustomTagChips(selected: $flavors, customOnly: flavors.subtracting(Set(flavorTags)))
                    Text("Libre — 8 goûts max au total")
                        .font(.system(size: Theme.Font.lead * 0.94))
                        .foregroundStyle(Theme.muted)
                }
                .beerCard()
            }
            if showHops {
                if !hopTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        FlavorTagGrid(title: "Houblons", tags: hopTags, selected: $hops, maxCount: 6)
                    }
                    .beerCard()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Houblons perso")
                        .font(.system(size: Theme.Font.tagTitle, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    CustomTagInput(
                        placeholder: "ex. Citra, Mosaic, Galaxy…",
                        input: $customHopInput,
                        selected: $hops,
                        maxCount: 6,
                        onRegister: { name in Task { try? await app.api.addHop(name) } }
                    )
                    CustomTagChips(selected: $hops, customOnly: hops.subtracting(Set(hopTags)))
                    Text("Max ~6 houblons")
                        .font(.system(size: Theme.Font.lead * 0.94))
                        .foregroundStyle(Theme.muted)
                }
                .beerCard()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Commentaire (optionnel, 120 car.)")
                    .font(.system(size: Theme.Font.tagTitle, weight: .semibold))
                    .foregroundStyle(Theme.text)
                TextField("Terrasse, avec elle, à refaire…", text: $comment, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: comment, perform: { v in
                        if v.count > 120 { comment = String(v.prefix(120)) }
                    })
                    .padding(12)
                    .background(Theme.fieldBg)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Theme.text)
                Text("\(comment.count)/120")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .beerCard()

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
            app.showToast("Code-barres trop court", variant: .warn)
            return
        }
        busy = true
        scanStatus = "Recherche…"
        defer { busy = false }

        if app.networkStatus != .online {
            scannedCode = digits
            scanStatus = "Hors ligne — saisie manuelle ou Untappd"
            return
        }

        do {
            let res = try await app.api.lookup(barcode: digits)
            if res.ok {
                product = res.asProduct(fallbackBarcode: digits)
                scanStatus = "Bière identifiée ✓"
                app.showToast("Bière identifiée ✓", variant: .success)
            } else {
                product = nil
                scannedCode = digits
                scanStatus = res.error ?? "Introuvable"
                app.showToast(res.error ?? "Bière introuvable", variant: .warn)
            }
        } catch let err {
            scanStatus = err.localizedDescription
        }
    }

    private func processScanPhoto(_ image: UIImage) async {
        guard let raw = image.jpegData(compressionQuality: 0.92) else { return }
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
                app.showToast(
                    "Code-barres lu ✓",
                    variant: .success,
                    detail: digits.isEmpty ? nil : digits,
                    label: "Scan photo",
                    durationMs: 2400
                )
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
        if digits.count >= 8, app.networkStatus == .online {
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

    private func processTastingPhoto(_ image: UIImage) async {
        guard let raw = image.jpegData(compressionQuality: 0.92) else { return }
        let jpeg = BeerImageUtils.compressJPEG(raw)
        photoData = jpeg
        photoPreview = UIImage(data: jpeg)
    }

    private func loadNotation() async {
        guard let product, app.networkStatus == .online else { return }
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
            let variant: ToastPayload.Variant = msg.contains("✓") ? .success
                : msg.contains("iPhone") ? .info : .success
            app.showToast(msg, variant: variant)
            app.hapticSuccess()
            try? await Task.sleep(nanoseconds: 900_000_000)
            resetWizard()
        } catch let err {
            app.showToast(err.localizedDescription, variant: .error, durationMs: 4200)
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
            app.showToast("Ajouté à « À boire » ✓", variant: .success)
        } catch let err {
            app.showToast(err.localizedDescription, variant: .error)
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
        photoData = nil
        photoPreview = nil
        rating = 3.0
        comment = ""
        flavors = []
        hops = []
        customFlavorInput = ""
        customHopInput = ""
        scanStatus = "Cadre le code-barres dans le rectangle"
        duplicateDetail = ""
    }
}