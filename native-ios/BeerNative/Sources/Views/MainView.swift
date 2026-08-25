import SwiftUI

// Vues de support extraites vers MainViewOverlays.swift (AppUpdateBanner,
// LootSummaryKey/Sheet, AccountMenuOverlay, FeedbackSheetView,
// FeedbackReplyKey/Popup), PendingSheetView.swift et SettingsSheetView.swift
// (+ extension BeerOfflineCache).

enum BeerSheet: String, Identifiable {
    case history, gallery, wishlist, gifts, admin, patchnotes, pending, grimoire, rpgAdmin, tutorial
    var id: String { rawValue }
}

struct MainView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sheet: BeerSheet?
    @State private var showLogoutConfirm = false
    @State private var showAccountMenu = false
    @State private var showFeedback = false
    @Environment(\.scenePhase) private var scenePhase

    private var logoutWarning: String {
        if app.isInvite || InviteSessionStore.hasInviteSession {
            return "Tu perds l'accès sur cet iPhone. Il faudra un nouveau lien d'invitation pour revenir."
        }
        return "Tu devras te reconnecter (Wi‑Fi maison ou VPN) pour accéder à Beer Quest."
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
                if app.needsAppUpdate {
                    AppUpdateBanner(
                        current: app.appVersion,
                        latest: app.latestIosVersion ?? "?",
                        portalURL: app.portalURL
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
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
                    appVersionLine: accountVersionLine,
                    needsUpdate: app.needsAppUpdate,
                    latestIos: app.latestIosVersion,
                    isCheckingMaj: app.isCheckingMaj,
                    isInvite: app.isInvite,
                    isAdmin: app.isAdmin,
                    rpgActive: app.rpgActive,
                    pendingCount: app.pendingCount,
                    portalURL: app.portalURL,
                    onDismiss: { showAccountMenu = false },
                    onOpen: { s in
                        showAccountMenu = false
                        if s == .grimoire {
                            Task { await app.refreshRpg() }
                        }
                        sheet = s
                    },
                    onCheckMaj: {
                        showAccountMenu = false
                        Task { await app.checkMaj() }
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(
            get: { app.currentFeedbackReply.map { FeedbackReplyKey(item: $0) } },
            set: { if $0 == nil { /* fermeture via bouton */ } }
        )) { key in
            FeedbackReplyPopup(
                item: key.item,
                index: app.feedbackReplyIndex,
                total: app.pendingFeedbackReplies.count,
                onNext: { app.advanceFeedbackReply() }
            )
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(true)
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
            case .tutorial:
                TutorialSheetView(onClose: {
                    Task { await app.markTutorialSeen() }
                })
            case .pending:
                PendingSheetView()
                    .environmentObject(app)
            case .grimoire:
                GrimoireSheetView()
                    .environmentObject(app)
            case .rpgAdmin:
                BeerquestAdminSheetView()
                    .environmentObject(app)
            }
        }
        .environmentObject(app)
        .sheet(item: Binding(
            get: { app.lootSummary.map { LootSummaryKey(loot: $0) } },
            set: { if $0 == nil { app.dismissLootSummary() } }
        )) { key in
            LootSummarySheet(loot: key.loot) {
                app.dismissLootSummary()
            }
            .environmentObject(app)
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await app.refreshMobileVersions()
        }
        .onChange(of: app.showTutorial) { want in
            if want {
                app.showTutorial = false
                sheet = .tutorial
            }
        }
        .onChange(of: app.requestOpenGrimoire) { want in
            if want {
                app.requestOpenGrimoire = false
                Task { await app.refreshRpg() }
                sheet = .grimoire
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await app.onAppResumed() }
            }
        }
    }

    /// Titre + Check MAJ + Mon compte (parité Android).
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Beer Quest")
                    .font(.system(size: Theme.Font.h1, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(headerSubtitle)
                    .font(.system(size: Theme.Font.sub))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Button {
                Task { await app.checkMaj() }
            } label: {
                Text(app.isCheckingMaj ? "…" : "MAJ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
            }
            .disabled(app.isCheckingMaj)
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

    private var headerSubtitle: String {
        let appV = "IPA \(app.appVersion)"
        if app.serverVersion.isEmpty {
            return appV
        }
        return "\(appV) · web \(app.serverVersion)"
    }

    private var accountVersionLine: String {
        var s = "IPA \(app.appVersion)"
        if !app.serverVersion.isEmpty {
            s += " · web \(app.serverVersion)"
        }
        if app.needsAppUpdate, let latest = app.latestIosVersion {
            s += " · ⬆️ \(latest) dispo"
        }
        return s
    }
}
