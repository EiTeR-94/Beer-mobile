import SwiftUI

enum BeerSheet: String, Identifiable {
    case history, gallery, wishlist, gifts, admin, patchnotes
    var id: String { rawValue }
}

struct MainView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("inviteHelpDismissed") private var inviteHelpDismissed = false
    @State private var sheet: BeerSheet?
    @State private var globalSearch = ""
    @State private var historySearchSeed = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if app.isInvite && !inviteHelpDismissed {
                InviteHelpBar { inviteHelpDismissed = true }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            BeerStepNav(step: $app.wizardStep)
            BeerWizardView(step: $app.wizardStep)
        }
        .background(Theme.bg)
        .sheet(item: $sheet) { s in
            switch s {
            case .history:
                HistorySheetView(initialSearch: historySearchSeed, onOpenGallery: { sheet = .gallery })
                    .beerSheetChrome()
            case .gallery:
                GallerySheetView()
                    .beerSheetChrome()
            case .wishlist:
                WishlistSheetView()
                    .beerSheetChrome()
            case .gifts:
                GiftsSheetView()
                    .beerSheetChrome()
            case .admin:
                AdminSheetView()
                    .beerSheetChrome()
            case .patchnotes:
                PatchnotesSheetView()
                    .beerSheetChrome()
            }
        }
        .environmentObject(app)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Beer Log")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(app.serverVersion.isEmpty ? "scan · photo · note" : "v\(app.serverVersion) · scan · photo · note")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if !app.isOnline { OfflineBadge() }
                    if let user = app.user {
                        Text(userPillText(user))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.card)
                            .overlay(Capsule().stroke(Theme.border))
                            .clipShape(Capsule())
                    }
                }
            }

            if app.isAdmin {
                HStack(spacing: 8) {
                    headerBtn("Admin", accent: true) { sheet = .admin }
                    headerBtn("Patch notes") { sheet = .patchnotes }
                    Spacer()
                }
            }

            TextField("Rechercher…", text: $globalSearch)
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit {
                    historySearchSeed = globalSearch
                    sheet = .history
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !app.isInvite {
                        headerBtn("À boire") { sheet = .wishlist }
                    }
                    headerBtn("Historique") { sheet = .history }
                    headerBtn("Galerie") { sheet = .gallery }
                    if !app.isInvite {
                        headerBtn("Idées cadeaux") { sheet = .gifts }
                    }
                    if !app.isInvite {
                        headerBtn("Déconnexion", destructive: true) { Task { await app.logout() } }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func userPillText(_ user: String) -> String {
        if app.isAdmin { return "\(user) · admin" }
        if app.isInvite { return "\(user) · invité" }
        return user
    }

    private func headerBtn(
        _ title: String,
        destructive: Bool = false,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: accent ? .semibold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(destructive ? Color.clear : accent ? Theme.accent.opacity(0.18) : Theme.card)
                .foregroundStyle(destructive ? Theme.error : accent ? Theme.accent : Theme.text)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                    destructive ? Theme.error.opacity(0.5) : accent ? Theme.accent.opacity(0.5) : Theme.border
                ))
        }
    }
}