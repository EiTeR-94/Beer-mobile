import SwiftUI

struct ScanTabView: View {
    @EnvironmentObject private var app: AppModel
    @State private var scannedCode = ""
    @State private var manualCode = ""
    @State private var product: BeerProduct?
    @State private var manualName = ""
    @State private var manualBrewery = ""
    @State private var status = "Vise le code EAN"
    @State private var busy = false
    @State private var showCheckin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack(alignment: .bottom) {
                        BarcodeScannerView { code in
                            scannedCode = code
                            manualCode = code
                            Task { await lookup(code) }
                        }
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.5), lineWidth: 2))

                        Text(status)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(12)
                    }

                    HStack {
                        TextField("EAN manuel", text: $manualCode)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button("Chercher") {
                            Task { await lookup(manualCode) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }

                    if let product, !product.beerName.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(product.beerName)
                                .font(.title3.bold())
                            Text([product.brewery, product.displayStyle].filter { !$0.isEmpty }.joined(separator: " · "))
                                .foregroundStyle(Theme.muted)
                            if !product.barcode.isEmpty {
                                Text("EAN \(product.barcode)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Button("Noter cette bière") { showCheckin = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .beerCard()
                    } else if !scannedCode.isEmpty && !busy {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bière non identifiée — saisie manuelle")
                                .font(.headline)
                            TextField("Nom de la bière", text: $manualName)
                                .padding(12)
                                .background(Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            TextField("Brasserie", text: $manualBrewery)
                                .padding(12)
                                .background(Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Button("Continuer") {
                                product = BeerProduct(
                                    barcode: scannedCode,
                                    beerName: manualName,
                                    brewery: manualBrewery.isEmpty ? "—" : manualBrewery,
                                    style: "Unknown"
                                )
                                showCheckin = true
                            }
                            .disabled(manualName.count < 2)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }
                        .beerCard()
                    }
                }
                .padding(16)
                .padding(.top, 48)
            }
            .background(Theme.bg)
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCheckin) {
                if let product {
                    CheckinFormView(product: product) {
                        self.product = nil
                        self.scannedCode = ""
                        self.manualName = ""
                        self.manualBrewery = ""
                        self.status = "Vise le code EAN"
                    }
                }
            }
        }
    }

    private func lookup(_ code: String) async {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 8 else {
            status = "Code trop court"
            return
        }
        busy = true
        status = "Recherche…"
        defer { busy = false }

        if !app.isOnline {
            scannedCode = digits
            status = "Hors ligne — saisis le nom ci-dessous"
            product = nil
            return
        }

        do {
            let res = try await app.api.lookup(barcode: digits)
            if res.ok {
                product = res.asProduct(fallbackBarcode: digits)
                status = "Bière identifiée ✓"
            } else {
                product = nil
                scannedCode = digits
                status = res.error ?? "Introuvable — saisie manuelle"
            }
        } catch {
            product = nil
            scannedCode = digits
            status = error.localizedDescription
        }
    }
}