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
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
            BeerStepNav(step: $app.wizardStep)
            BeerWizardView(step: $app.wizardStep)
        }
        .background(Theme.bg)
        .fullScreenCover(item: $sheet) { s in
            switch s {
            case .history:
                HistorySheetView(initialSearch: historySearchSeed, onOpenGallery: { sheet = .gallery })
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
            }
        }
        .environmentObject(app)
    }

    /// Même structure que `header.top` + `div.top-actions` (PWA).
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Beer Log")
                    .font(.system(size: Theme.Font.h1, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(app.serverVersion.isEmpty ? "scan · photo · note" : "v\(app.serverVersion) · scan · photo · note")
                    .font(.system(size: Theme.Font.sub))
                    .foregroundStyle(Theme.muted)
            }
            .layoutPriority(1)

            FlowLayout(spacing: 6) {
                if let user = app.user {
                    Text(user)
                        .font(.system(size: Theme.Font.pill))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Theme.border))
                }

                TextField("Rechercher...", text: $globalSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: Theme.Font.search))
                    .frame(width: 130)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        historySearchSeed = globalSearch
                        sheet = .history
                    }

                if app.isAdmin {
                    BeerGhostButton("Patch notes") { sheet = .patchnotes }
                    BeerGhostButton("Admin") { sheet = .admin }
                }
                if !app.isInvite {
                    BeerGhostButton("À boire") { sheet = .wishlist }
                }
                BeerGhostButton("Historique") { sheet = .history }
                if !app.isInvite {
                    BeerGhostButton("Idées cadeaux") { sheet = .gifts }
                }
                if !app.isInvite {
                    BeerGhostButton("Déconnexion") { Task { await app.logout() } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Theme.bg)
    }
}