import SwiftUI

enum BeerSheet: String, Identifiable {
    case history, gallery, wishlist, gifts, admin, patchnotes, pending, grimoire
    var id: String { rawValue }
}

struct MainView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sheet: BeerSheet?
    @State private var showLogoutConfirm = false
    @State private var showAccountMenu = false
    @State private var showFeedback = false

    private var logoutWarning: String {
        if app.isInvite || InviteSessionStore.hasInviteSession {
            return "Tu perds l'accès sur cet iPhone. Il faudra un nouveau lien d'invitation pour revenir."
        }
        return "Tu devras te reconnecter (Wi‑Fi maison ou VPN) pour accéder à Beer Log."
    }

    private var connectedLabel: String {
        if app.isInvite {
            if let label = app.inviteLabel, !label.isEmpty { return "invité · \(label)" }
            return "invité"
        }
        return app.user ?? "—"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                if app.isLoggedIn, app.networkStatus != .online || app.pendingCount > 0 {
                    NetworkStatusBar(status: app.networkStatus, pending: app.pendingCount, latency: app.lastEndpointLatency)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                if app.rpgActive, let p = app.rpgState?.profile {
                    BqHudCard(profile: p) {
                        Task { await app.refreshRpg() }
                        sheet = .grimoire
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                BeerStepNav(step: $app.wizardStep)
                BeerWizardView(step: $app.wizardStep)
            }
            .background(Theme.bg)

            if showAccountMenu {
                AccountMenuOverlay(
                    connectedLabel: connectedLabel,
                    isInvite: app.isInvite,
                    isAdmin: app.isAdmin,
                    rpgActive: app.rpgActive,
                    pendingCount: app.pendingCount,
                    onDismiss: { showAccountMenu = false },
                    onOpen: { s in
                        showAccountMenu = false
                        if s == .grimoire {
                            Task { await app.refreshRpg() }
                        }
                        sheet = s
                    },
                    onFeedback: {
                        showAccountMenu = false
                        showFeedback = true
                    },
                    onLogout: {
                        showAccountMenu = false
                        showLogoutConfirm = true
                    }
                )
            }
        }
        // confirmationDialog AVANT fullScreenCover — sinon l'alerte ne sort pas (bug SwiftUI)
        .confirmationDialog(
            "Se déconnecter ?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Se déconnecter", role: .destructive) {
                Task { await app.logout() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(logoutWarning)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheetView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $sheet) { s in
            switch s {
            case .history:
                HistorySheetView(onOpenGallery: { sheet = .gallery })
            case .gallery:
                GallerySheetView()
            case .wishlist:
                WishlistSheetView()
            case .gifts:
                GiftsSheetView()
            case .admin:
                AdminSheetView()
            case .patchnotes:
                PatchnotesSheetView()
            case .pending:
                PendingSheetView()
                    .environmentObject(app)
            case .grimoire:
                GrimoireSheetView()
                    .environmentObject(app)
            }
        }
        .environmentObject(app)
    }

    /// Titre + bouton Mon compte (parité PWA).
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Beer Log")
                    .font(.system(size: Theme.Font.h1, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(app.serverVersion.isEmpty ? "scan · photo · note" : "v\(app.serverVersion) · scan · photo · note")
                    .font(.system(size: Theme.Font.sub))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Button {
                showAccountMenu = true
            } label: {
                Text("Mon compte")
                    .font(.system(size: Theme.Font.ghost, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Theme.bg)
    }
}

// MARK: - Mon compte (parité PWA)

private struct AccountMenuOverlay: View {
    let connectedLabel: String
    let isInvite: Bool
    let isAdmin: Bool
    let rpgActive: Bool
    let pendingCount: Int
    let onDismiss: () -> Void
    let onOpen: (BeerSheet) -> Void
    let onFeedback: () -> Void
    let onLogout: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connecté")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Text(connectedLabel)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Text("×")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        section("Journal")
                        item("📜 Historique") { onOpen(.history) }
                        if !isInvite {
                            item("🍺 À boire") { onOpen(.wishlist) }
                            item("🎁 Idées cadeaux") { onOpen(.gifts) }
                        }
                        if rpgActive {
                            item("📖 Grimoire") { onOpen(.grimoire) }
                        }
                        if pendingCount > 0 {
                            item("⏳ En attente (\(pendingCount))") { onOpen(.pending) }
                        }

                        section("Parler à l’admin")
                        item("💬 Un retour") { onFeedback() }

                        if isAdmin {
                            section("Admin")
                            item("⚙️ Administration") { onOpen(.admin) }
                            item("📝 Patch notes") { onOpen(.patchnotes) }
                        }

                        section("Session")
                        item("Déconnexion", danger: true) { onLogout() }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: 320)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
            .clipShape(RoundedCornerShape(16))
            .padding(.top, 56)
            .padding(.trailing, 12)
            .padding(.leading, 48)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func item(_ title: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(danger ? Theme.error : Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}

private struct FeedbackSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var category = "general"
    @State private var sending = false

    private let categories: [(String, String)] = [
        ("general", "Un avis général"),
        ("bug", "Un bug"),
        ("idea", "Une idée"),
        ("ux", "L’interface"),
        ("rpg", "Le RPG / la progression"),
        ("other", "Autre chose"),
    ]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Dis-nous ce qui va, ce qui coince ou une idée. Seul l’admin le lit.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Section("C’est plutôt…") {
                    Picker("Catégorie", selection: $category) {
                        ForEach(categories, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Ton message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Envoi…" : "Envoyer") {
                        Task {
                            sending = true
                            let ok = await app.sendFeedback(message: message.trimmingCharacters(in: .whitespacesAndNewlines), category: category)
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
    }
}

// MARK: - Pending (2)

struct PendingSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Créations en attente") {
                    if app.pendingItems.isEmpty {
                        Text("Aucune dégustation en attente.")
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(app.pendingItems) { pending in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pending.beerName)
                                    .font(.headline)
                                Text("\(pending.brewery) · \(pending.style) · ★\(String(format: "%.1f", pending.rating))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                if !pending.comment.isEmpty {
                                    Text(pending.comment)
                                        .font(.caption)
                                }
                                Text(pending.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    app.removePending(id: pending.id)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                Section("Suppressions en attente") {
                    if app.pendingDeletes.isEmpty {
                        Text("Aucune suppression en attente.")
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(app.pendingDeletes, id: \.self) { delId in
                            HStack {
                                Text("Suppression #\(delId)")
                                Spacer()
                                Text("en file")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    app.removePendingDelete(id: delId)
                                } label: {
                                    Label("Annuler", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("En attente (\(app.pendingCount))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Synchroniser") {
                        Task {
                            await app.syncPending()
                            dismiss()
                        }
                    }
                    .disabled(app.pendingCount == 0)
                }
            }
        }
    }
}

// MARK: - Settings + Diagnostics (5)

struct SettingsSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var diagnosticResult: String = ""
    @State private var isTesting = false

    var body: some View {
        NavigationView {
            Form {
                Section("Connexion") {
                    HStack {
                        Text("Endpoint actif")
                        Spacer()
                        Text(app.api.activeEndpoint.isEmpty ? "—" : app.api.activeEndpoint)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("Statut réseau")
                        Spacer()
                        Text(app.networkStatus.label)
                            .foregroundStyle(networkColor)
                    }
                    Button {
                        Task {
                            isTesting = true
                            diagnosticResult = await app.testServer()
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Text("Tester les endpoints")
                            if isTesting { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(isTesting)

                    if !diagnosticResult.isEmpty {
                        Text(diagnosticResult)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Section("Cache & Offline") {
                    HStack {
                        Text("Éléments en attente")
                        Spacer()
                        Text("\(app.pendingCount)")
                    }
                    Button("Vider le cache offline") {
                        app.cache.clearAll()
                        app.cache.prune()
                        diagnosticResult = "Cache vidé + élagué."
                    }
                }

                Section("Sécurité") {
                    Text("Pinning activé pour le domaine (SPKI hash vérifié)")
                        .font(.caption)
                    Text("Politique domaine pour IPs LAN 192.168.x")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Section("Diagnostic") {
                    Button("Rafraîchir tout (history + gallery + stats)") {
                        Task {
                            await app.bootstrap()
                            diagnosticResult = "Rafraîchi."
                        }
                    }
                    Text("Version serveur: \(app.serverVersion.isEmpty ? "inconnue" : app.serverVersion)")
                }

                Section("Application (Theme 2)") {
                    let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(marketing) (\(build))")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Text("Build exposé pour debug (corr. audit)")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Paramètres & Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var networkColor: Color {
        switch app.networkStatus {
        case .online: return Theme.ok
        case .serverUnreachable: return Theme.accent
        case .offline: return Theme.error
        }
    }
}

extension BeerOfflineCache {
    func clearAll() {
        let fm = FileManager.default
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("offline-cache", isDirectory: true)
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files {
                try? fm.removeItem(at: f)
            }
        }
    }
}