import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var mode: LoginMode = .owner
    @State private var username = ""
    @State private var password = ""
    @State private var inviteLink = ""
    @State private var error: String?
    @State private var busy = false

    private enum LoginMode {
        case owner, invite
    }

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
                    .padding(.bottom, 16)

                    HStack(spacing: 8) {
                        modeButton(title: "Compte", selected: mode == .owner) {
                            mode = .owner
                            error = nil
                        }
                        modeButton(title: "Invitation", selected: mode == .invite) {
                            mode = .invite
                            error = nil
                        }
                    }
                    .padding(.bottom, 16)

                    VStack(spacing: 0) {
                        if mode == .owner {
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

                            BeerPrimaryButton(
                                title: busy ? "Connexion…" : "Se connecter",
                                disabled: username.isEmpty || password.isEmpty || busy,
                                busy: busy
                            ) {
                                Task { await submitOwner() }
                            }
                            Text("Wi‑Fi maison ou VPN Plexi requis")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 10)
                        } else {
                            Text("Colle le lien d'invitation reçu (WhatsApp, SMS…). Fonctionne en 4G/5G, sans VPN.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 14)

                            BeerField(
                                label: "Lien d'invitation",
                                text: $inviteLink,
                                placeholder: "https://eiter.freeboxos.fr/beer/join/…"
                            )
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

                            BeerPrimaryButton(
                                title: busy ? "Activation…" : "Activer l'invitation",
                                disabled: inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy,
                                busy: busy
                            ) {
                                Task { await submitInvite() }
                            }
                            Text("1 iPhone par invitation · pas de déconnexion")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 10)
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
        .onAppear {
            if let pending = app.pendingInviteLink, !pending.isEmpty {
                mode = .invite
                inviteLink = pending
            }
        }
        .onChange(of: app.pendingInviteLink) { newVal in
            if let newVal, !newVal.isEmpty {
                mode = .invite
                inviteLink = newVal
            }
        }
    }

    private func modeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(selected ? "• \(title)" : title)
                .font(.system(size: Theme.Font.ghost, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Theme.text)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(selected ? Theme.accent : Theme.border))
        }
    }

    private func submitOwner() async {
        await MainActor.run {
            busy = true
            error = nil
        }
        defer {
            Task { @MainActor in busy = false }
        }
        do {
            try await app.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }

    private func submitInvite() async {
        await MainActor.run {
            busy = true
            error = nil
        }
        // Message d'attente visible tout de suite (plus d'échec « instantané » sans feedback)
        await MainActor.run {
            error = nil
        }
        do {
            try await app.joinInvite(inviteLink: inviteLink.trimmingCharacters(in: .whitespacesAndNewlines))
            await MainActor.run { busy = false }
        } catch {
            await MainActor.run {
                busy = false
                // Affiche l'erreur réelle (plus de faux « Timeout 30s » inventé)
                self.error = error.localizedDescription
            }
        }
    }
}
