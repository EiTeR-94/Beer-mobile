import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var serverURL = ServerSettings.apiBaseString
    @State private var error: String?
    @State private var serverTestResult: String?
    @State private var serverTestOK = false
    @State private var testingServer = false
    @State private var busy = false
    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text("🍺")
                            .font(.system(size: 40))
                        Text("Beer Log")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("Journal de dégustation privé")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, 20)

                    VStack(spacing: 14) {
                        BeerField(label: "Identifiant", text: $username, placeholder: "")
                        BeerField(label: "Mot de passe", text: $password, secure: true)

                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        BeerPrimaryButton(title: busy ? "Connexion…" : "Se connecter", disabled: username.isEmpty || password.isEmpty, busy: busy) {
                            Task { await submit() }
                        }

                        DisclosureGroup("Réglages serveur", isExpanded: $showAdvanced) {
                            BeerField(
                                label: "URL Beer (LAN/VPN)",
                                text: $serverURL,
                                placeholder: "https://192.168.1.50:8444/beer/",
                                keyboard: .URL
                            )
                            .onChange(of: serverURL, perform: { app.applyServerURL($0) })
                            Button(testingServer ? "Test en cours…" : "Tester le serveur") {
                                Task { await runServerTest() }
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .disabled(testingServer)

                            if let serverTestResult {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(serverTestOK ? "✓" : "!")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(serverTestOK ? Theme.ok : Theme.error)
                                    Text(serverTestResult)
                                        .font(.caption)
                                        .foregroundStyle(serverTestOK ? Theme.ok : Theme.error)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(10)
                                .background((serverTestOK ? Theme.ok : Theme.error).opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                    (serverTestOK ? Theme.ok : Theme.error).opacity(0.25)
                                ))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .tint(Theme.accent)
                    }
                    .padding(20)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .beerShadow()

                    Text("Scan · photo · note · historique")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 20)
                }
                .padding(24)
            }
        }
        .onAppear {
            serverURL = ServerSettings.apiBaseString
            app.applyServerURL(serverURL)
        }
    }

    private func runServerTest() async {
        testingServer = true
        serverTestResult = nil
        defer { testingServer = false }
        app.applyServerURL(serverURL)
        let result = await app.testServer()
        serverTestOK = result.hasPrefix("Serveur OK")
        serverTestResult = result
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        app.applyServerURL(serverURL)
        do {
            try await app.login(username: username.trimmingCharacters(in: .whitespaces),
                                password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}