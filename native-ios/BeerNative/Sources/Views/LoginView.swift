import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var mode: LoginMode = .owner
    @State private var username = ""
    @State private var password = ""
    @State private var inviteLink = ""
    @State private var inviteEmail = ""
    @State private var error: String?
    @State private var busy = false
    @State private var clipboardHint: String?

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
                            Task { await prepareInviteFromClipboard(autoActivate: false) }
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
                            Text("Colle le lien (presse‑papiers), entre l'email que tu as donné, puis active. Aucun indice d'email dans l'app.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 14)

                            BeerSecondaryButton(title: "Coller le lien depuis le presse‑papiers") {
                                Task { await prepareInviteFromClipboard(autoActivate: false) }
                            }
                            .padding(.top, 10)

                            if let clipboardHint {
                                Text(clipboardHint)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.ok)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }

                            // Détail discret (token / lien détecté)
                            if !inviteLink.isEmpty {
                                Text(shortInvitePreview(inviteLink))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                                    .lineLimit(2)
                            }

                            BeerField(
                                label: "Ton email",
                                text: $inviteEmail,
                                placeholder: "celui que tu as donné"
                            )
                            .padding(.top, 12)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                            BeerPrimaryButton(
                                title: busy ? "Activation…" : "Activer l'invitation",
                                disabled: inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || busy,
                                busy: busy
                            ) {
                                Task { await submitInvite() }
                            }
                            .padding(.top, 12)

                            if let error {
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.error)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }

                            NetworkStatusBar(status: app.networkStatus)
                                .padding(.top, 8)

                            // Fallback si le lien n'est pas dans le presse-papiers
                            DisclosureGroup("Saisie manuelle du lien (rare)") {
                                BeerField(
                                    label: "Lien d'invitation",
                                    text: $inviteLink,
                                    placeholder: "https://eiter.freeboxos.fr/beer…/join/…"
                                )
                                .padding(.top, 10)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 12)

                            Text("1 iPhone · email requis · 4G/5G OK")
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
                clipboardHint = "Lien reçu — entre ton email pour activer"
                return
            }
            // Si un lien join est déjà dans le presse-papiers → onglet Invitation prêt
            if let clip = readInviteFromClipboard() {
                mode = .invite
                inviteLink = clip
                clipboardHint = "Lien d'invitation détecté dans le presse‑papiers"
            }
        }
        .onChange(of: app.pendingInviteLink) { newVal in
            if let newVal, !newVal.isEmpty {
                mode = .invite
                inviteLink = newVal
                clipboardHint = "Lien reçu — entre ton email pour activer"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard mode == .invite, !busy, inviteLink.isEmpty else { return }
            Task { await prepareInviteFromClipboard(autoActivate: false) }
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

    private func shortInvitePreview(_ raw: String) -> String {
        if let t = InviteSessionStore.parseInviteToken(raw) {
            let head = String(t.prefix(10))
            let tail = String(t.suffix(6))
            return "Token : \(head)…\(tail)"
        }
        return String(raw.prefix(48)) + (raw.count > 48 ? "…" : "")
    }

    /// Lit le presse-papiers et ne garde qu'un lien/token d'invitation Beer valide.
    private func readInviteFromClipboard() -> String? {
        guard let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        // URL join ou token brut
        if InviteSessionStore.parseInviteToken(s) != nil {
            return s
        }
        // Cherche une URL join dans un texte collé plus large
        if let range = s.range(of: #"https?://[^\s]+/beer(?:-alpha)?/join/[A-Za-z0-9_-]{24,}"#, options: .regularExpression) {
            let url = String(s[range])
            if InviteSessionStore.parseInviteToken(url) != nil { return url }
        }
        return nil
    }

    @MainActor
    private func prepareInviteFromClipboard(autoActivate: Bool) async {
        guard let clip = readInviteFromClipboard() else {
            clipboardHint = nil
            if autoActivate {
                error = "Aucun lien d'invitation dans le presse‑papiers — copie le lien reçu puis réessaie"
            }
            return
        }
        inviteLink = clip
        clipboardHint = "Lien prêt — entre ton email puis active"
        error = nil
        // Jamais d'auto-activation : l'email doit être saisi
    }

    private func activateFromClipboard() async {
        await prepareInviteFromClipboard(autoActivate: false)
        await submitInvite()
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
        let (link, email) = await MainActor.run { () -> (String, String) in
            busy = true
            error = nil
            return (
                inviteLink.trimmingCharacters(in: .whitespacesAndNewlines),
                inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !link.isEmpty else {
            await MainActor.run {
                busy = false
                error = "Lien d'invitation manquant"
            }
            return
        }
        guard !email.isEmpty, email.contains("@") else {
            await MainActor.run {
                busy = false
                error = "Entre l'email que tu as donné pour l'invitation"
            }
            return
        }
        do {
            try await app.joinInvite(inviteLink: link, email: email)
            await MainActor.run {
                busy = false
                app.pendingInviteLink = nil
            }
        } catch {
            await MainActor.run {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }
}
