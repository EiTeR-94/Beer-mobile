import SwiftUI

enum BeerSheet: String, Identifiable {
    case history, gallery, wishlist, gifts, admin, patchnotes, pending, settings
    var id: String { rawValue }
}

struct MainView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("inviteHelpDismissed") private var inviteHelpDismissed = false
    @State private var sheet: BeerSheet?
    @State private var showInviteLogoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.isInvite && !inviteHelpDismissed {
                InviteHelpBar { inviteHelpDismissed = true }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            if app.isLoggedIn, app.networkStatus != .online || app.pendingCount > 0 {
                NetworkStatusBar(status: app.networkStatus, pending: app.pendingCount)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            BeerStepNav(step: $app.wizardStep)
            BeerWizardView(step: $app.wizardStep)
        }
        .background(Theme.bg)
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
            case .settings:
                SettingsSheetView()
                    .environmentObject(app)
            }
        }
        .environmentObject(app)
        .alert("Se déconnecter ?", isPresented: $showInviteLogoutConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Déconnexion", role: .destructive) {
                Task { await app.logout() }
            }
        } message: {
            Text(
                "En te déconnectant, tu perdras l'accès à Beer Log sur cet appareil. "
                    + "Tu ne pourras pas revenir sans un nouveau lien d'invitation."
            )
        }
    }

    /// Titre + boutons en grille (évite le wrap brouillon du FlowLayout sur iPhone).
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Beer Log")
                        .font(.system(size: Theme.Font.h1, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(app.serverVersion.isEmpty ? "scan · photo · note" : "v\(app.serverVersion) · scan · photo · note")
                        .font(.system(size: Theme.Font.sub))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if let user = app.user {
                    Text(user)
                        .font(.system(size: Theme.Font.pill))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Theme.border))
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                ForEach(headerButtons, id: \.title) { btn in
                    Button(action: btn.action) {
                        Text(btn.title)
                            .font(.system(size: Theme.Font.ghost, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.clear)
                            .foregroundStyle(Theme.text)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Theme.bg)
    }

    private struct HeaderButton {
        let title: String
        let action: () -> Void
    }

    private var headerButtons: [HeaderButton] {
        var buttons: [HeaderButton] = []
        if app.isAdmin {
            buttons.append(HeaderButton(title: "Patch notes") { sheet = .patchnotes })
            buttons.append(HeaderButton(title: "Admin") { sheet = .admin })
        }
        if !app.isInvite {
            buttons.append(HeaderButton(title: "À boire") { sheet = .wishlist })
        }
        buttons.append(HeaderButton(title: "Historique") { sheet = .history })
        if !app.isInvite {
            buttons.append(HeaderButton(title: "Idées cadeaux") { sheet = .gifts })
        }
        if app.pendingCount > 0 {
            buttons.append(HeaderButton(title: "En attente (\(app.pendingCount))") { sheet = .pending })
        }
        buttons.append(HeaderButton(title: "⚙︎ Paramètres") { sheet = .settings })
        if app.isInvite {
            buttons.append(HeaderButton(title: "Déconnexion") { showInviteLogoutConfirm = true })
        } else {
            buttons.append(HeaderButton(title: "Déconnexion") { Task { await app.logout() } })
        }
        return buttons
    }
}

// MARK: - Pending (2)

struct PendingSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
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
                        diagnosticResult = "Cache vidé."
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