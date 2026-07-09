import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var biometricsUnavailable = !PasskeyAuth.biometricsAvailable

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("🍺")
                        .font(.system(size: 40))
                    Text("Beer Log")
                        .font(.system(size: Theme.Font.h1, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Journal de dégustation privé")
                        .font(.system(size: Theme.Font.sub))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    BeerField(label: "Identifiant", text: $username, placeholder: "")
                        .padding(.top, 14)
                    BeerField(label: "Mot de passe", text: $password, secure: true)
                        .padding(.top, 14)

                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }

                    NetworkStatusBar(status: app.networkStatus)
                        .padding(.top, 8)

                    BeerPrimaryButton(title: busy ? "Connexion…" : "Se connecter", disabled: username.isEmpty || password.isEmpty, busy: busy) {
                        Task { await submit() }
                    }

                    if biometricsUnavailable {
                        Text("Biométrie indisponible sur cet appareil.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 360)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Text("Scan · photo · note · historique")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 20)
            }
            .padding(24)
        }
    }

    private func submit() async {
        await MainActor.run {
            busy = true
            error = nil
        }
        defer {
            Task { @MainActor in busy = false }
        }
        do {
            try await app.login(username: username.trimmingCharacters(in: .whitespaces),
                                password: password)
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}