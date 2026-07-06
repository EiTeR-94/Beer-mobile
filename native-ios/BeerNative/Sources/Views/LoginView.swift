import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var serverURL = ServerSettings.apiBaseString
    @State private var error: String?
    @State private var serverStatus: String?
    @State private var busy = false
    @State private var testing = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("🍺")
                            .font(.system(size: 56))
                        Text("Plexi Beer")
                            .font(.title.bold())
                            .foregroundStyle(Theme.accent)
                        Text("App native iOS")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }

                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Serveur Beer")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            TextField("https://…:8444/beer", text: $serverURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(12)
                                .background(Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .onChange(of: serverURL) { _, v in
                                    app.applyServerURL(v)
                                }
                            Button {
                                Task { await testServer() }
                            } label: {
                                Text(testing ? "Test…" : "Tester le serveur")
                                    .font(.caption.weight(.medium))
                            }
                            .disabled(testing)
                            if let serverStatus {
                                Text(serverStatus)
                                    .font(.caption2)
                                    .foregroundStyle(serverStatus.hasPrefix("Serveur OK") ? .green : .red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        TextField("Identifiant", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Theme.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        SecureField("Mot de passe", text: $password)
                            .padding()
                            .background(Theme.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.black) }
                                Text(busy ? "Connexion…" : "Se connecter")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(busy || username.isEmpty || password.isEmpty)
                    }
                    .beerCard()

                    Text("Wi‑Fi maison ou VPN Plexi · port 8444 (pas 8443).")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .onAppear {
            serverURL = ServerSettings.apiBaseString
            app.applyServerURL(serverURL)
        }
    }

    private func testServer() async {
        testing = true
        defer { testing = false }
        app.applyServerURL(serverURL)
        serverStatus = await app.testServer()
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        app.applyServerURL(serverURL)
        do {
            try await app.login(username: username.trimmingCharacters(in: .whitespaces),
                                password: password)
        } catch let err {
            self.error = err.localizedDescription
        }
    }
}