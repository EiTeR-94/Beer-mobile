import SwiftUI

enum BeerSheet: String, Identifiable {
    case history, gallery, wishlist, gifts, admin, patchnotes
    var id: String { rawValue }
}

struct MainView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sheet: BeerSheet?
    @State private var globalSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let banner = app.banner {
                Text(banner).font(.caption).foregroundStyle(Theme.accent).padding(.horizontal, 16)
            }
            BeerStepNav(step: $app.wizardStep)
            BeerWizardView(step: $app.wizardStep)
        }
        .background(Theme.bg)
        .sheet(item: $sheet) { s in
            switch s {
            case .history: HistorySheetView()
            case .gallery: GallerySheetView()
            case .wishlist: WishlistSheetView()
            case .gifts: GiftsSheetView()
            case .admin: AdminSheetView()
            case .patchnotes: PatchnotesSheetView()
            }
        }
        .environmentObject(app)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Beer Log").font(.system(size: 22, weight: .bold))
                    Text(app.serverVersion.isEmpty ? "scan · photo · note" : "v\(app.serverVersion) · scan · photo · note")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if let user = app.user {
                    Text(user)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.card)
                        .overlay(Capsule().stroke(Theme.border))
                        .clipShape(Capsule())
                }
            }

            TextField("Rechercher…", text: $globalSearch)
                .textInputAutocapitalization(.never)
                .padding(10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit { sheet = .history }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    headerBtn("À boire") { sheet = .wishlist }
                    headerBtn("Historique") { sheet = .history }
                    headerBtn("Galerie") { sheet = .gallery }
                    headerBtn("Idées cadeaux") { sheet = .gifts }
                    if app.isAdmin {
                        headerBtn("Admin") { sheet = .admin }
                        headerBtn("Patch notes") { sheet = .patchnotes }
                    }
                    headerBtn("Déconnexion", destructive: true) { Task { await app.logout() } }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.bg)
    }

    private func headerBtn(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(destructive ? Color.clear : Theme.card)
                .foregroundStyle(destructive ? Theme.error : Theme.text)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(destructive ? Theme.error.opacity(0.5) : Theme.border))
        }
    }
}