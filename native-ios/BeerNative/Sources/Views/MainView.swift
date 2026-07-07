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

    /// Titre + recherche + boutons en grille (évite le wrap brouillon du FlowLayout sur iPhone).
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

            TextField("Rechercher...", text: $globalSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: Theme.Font.search))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Theme.fieldBg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    historySearchSeed = globalSearch
                    sheet = .history
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
        buttons.append(HeaderButton(title: "Historique") {
            historySearchSeed = globalSearch
            sheet = .history
        })
        if !app.isInvite {
            buttons.append(HeaderButton(title: "Idées cadeaux") { sheet = .gifts })
        }
        if !app.isInvite {
            buttons.append(HeaderButton(title: "Déconnexion") { Task { await app.logout() } })
        }
        return buttons
    }
}