import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var inviteLink = ""
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
                            .font(.system(size: Theme.Font.h1, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("Journal de dégustation privé")
                            .font(.system(size: Theme.Font.sub))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, 12)

                    Text("Compte perso : Wi‑Fi maison + DNS 192.168.1.50 sur l’iPhone (Réglages Wi‑Fi). Pas la 4G.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)

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

                        BeerPrimaryButton(title: busy ? "Connexion…" : "Se connecter", disabled: username.isEmpty || password.isEmpty, busy: busy) {
                            Task { await submit() }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 360)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(spacing: 0) {
                        Text("Invitation reçue ?")
                            .font(.system(size: Theme.Font.field, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)

                        BeerField(
                            label: "Lien d'invitation",
                            text: $inviteLink,
                            placeholder: "https://eiter.freeboxos.fr/beer/join/…",
                            keyboard: .URL
                        )

                        HStack(spacing: 8) {
                            Button {
                                if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !pasted.isEmpty {
                                    inviteLink = pasted
                                }
                            } label: {
                                Text("Coller")
                                    .font(.system(size: Theme.Font.ghost, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(Theme.text)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
                            }
                            .disabled(busy)

                            BeerPrimaryButton(
                                title: busy ? "Activation…" : "Activer",
                                disabled: inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                busy: busy
                            ) {
                                Task { await submitInvite() }
                            }
                        }
                        .padding(.top, 10)

                        Text("4G ou Wi‑Fi — colle le lien reçu puis Activer.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: 360)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.top, 16)

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

    private func submitInvite() async {
        busy = true
        error = nil
        defer { busy = false }
        await app.redeemInviteFromText(inviteLink)
    }
}