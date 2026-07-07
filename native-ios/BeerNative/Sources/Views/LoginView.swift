import SwiftUI

/// Conservé pour tests unitaires / archive — l'app charge la PWA via `BeerWebContainer`.
struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

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
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await app.login(username: username.trimmingCharacters(in: .whitespaces),
                                password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}