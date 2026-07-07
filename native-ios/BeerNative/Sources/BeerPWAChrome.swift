import SwiftUI

// MARK: - Overlay shell (history-head, wishlist-head, admin-head…)

struct BeerOverlayScreen<Content: View>: View {
    let title: String
    let onClose: () -> Void
    var trailing: [BeerHeadAction] = []
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            BeerOverlayHead(title: title, onClose: onClose, trailing: trailing)
            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

struct BeerHeadAction: Identifiable {
    let id = UUID()
    let title: String
    let primary: Bool
    let handler: () -> Void

    static func ghost(_ title: String, handler: @escaping () -> Void) -> BeerHeadAction {
        BeerHeadAction(title: title, primary: false, handler: handler)
    }

    static func primary(_ title: String, handler: @escaping () -> Void) -> BeerHeadAction {
        BeerHeadAction(title: title, primary: true, handler: handler)
    }
}

struct BeerOverlayHead: View {
    let title: String
    let onClose: () -> Void
    var trailing: [BeerHeadAction] = []

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: Theme.Font.h1, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                ForEach(trailing) { action in
                    if action.primary {
                        Button(action.title, action: action.handler)
                            .font(.system(size: Theme.Font.ghost, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.primaryGradient)
                            .foregroundStyle(Theme.btnPrimaryText)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
                    } else {
                        BeerGhostButton(action.title, action: action.handler)
                    }
                }
                BeerGhostButton("Fermer", action: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

// MARK: - Filtres PWA (grille 3 colonnes + recherche)

struct BeerFilterLabel<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BeerSelectField: View {
    let label: String
    let value: String
    let options: [(String, String)]
    let onSelect: (String) -> Void

    private var display: String {
        options.first(where: { $0.0 == value })?.1 ?? "—"
    }

    var body: some View {
        BeerFilterLabel(label: label) {
            Menu {
                ForEach(options, id: \.0) { opt in
                    Button(opt.1) { onSelect(opt.0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(display)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct BeerHistoryFiltersRow: View {
    @Binding var filterStyle: String
    @Binding var filterRating: Double
    @Binding var filterPeriod: String
    let styles: [StyleOption]

    private var styleOptions: [(String, String)] {
        var opts: [(String, String)] = [("", "Tous styles")]
        opts.append(contentsOf: styles.filter { !$0.value.isEmpty }.map { ($0.value, $0.label) })
        return opts
    }

    private var ratingOptions: [(String, String)] {
        var opts: [(String, String)] = [("0", "Toutes")]
        for val in [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0] {
            let key = val == floor(val) ? String(Int(val)) : String(val)
            let label = (val == floor(val) ? String(format: "%.0f", val) : String(format: "%.2f", val))
                .replacingOccurrences(of: ".00", with: "")
                .replacingOccurrences(of: ".50", with: ".5") + " ★+"
            opts.append((key, label))
        }
        return opts
    }

    private var ratingKey: String {
        let v = filterRating
        if v == 0 { return "0" }
        return v == floor(v) ? String(Int(v)) : String(v)
    }

    private var periodOptions: [(String, String)] {
        [("", "Tout"), ("week", "7 jours"), ("month", "30 jours"), ("year", "1 an")]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            BeerSelectField(label: "Style", value: filterStyle, options: styleOptions) { filterStyle = $0 }
            BeerSelectField(
                label: "Note min",
                value: ratingKey,
                options: ratingOptions
            ) { filterRating = Double($0) ?? 0 }
            BeerSelectField(label: "Période", value: filterPeriod, options: periodOptions) { filterPeriod = $0 }
        }
        .padding(.vertical, 8)
    }
}

struct BeerGiftsFiltersRow: View {
    @Binding var search: String
    @Binding var filterStyle: String
    @Binding var minRating: Double
    let styleOptions: [String]

    private var styles: [(String, String)] {
        var opts: [(String, String)] = [("", "Tous styles")]
        opts.append(contentsOf: styleOptions.map { ($0, $0) })
        return opts
    }

    private var ratingOptions: [(String, String)] {
        [("0", "Toutes"), ("4", "≥4★"), ("4.5", "≥4.5★"), ("5", "=5★")]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            BeerFilterLabel(label: "Recherche") {
                TextField("nom, brasserie...", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.text)
            }
            BeerSelectField(label: "Style", value: filterStyle, options: styles) { filterStyle = $0 }
            BeerSelectField(
                label: "Note min",
                value: minRating == 5 ? "5" : (minRating == 4.5 ? "4.5" : (minRating >= 4 ? "4" : "0")),
                options: ratingOptions
            ) { minRating = Double($0) ?? 0 }
        }
        .padding(.vertical, 8)
    }
}

struct BeerHistorySearchField: View {
    @Binding var text: String

    var body: some View {
        BeerFilterLabel(label: "Rechercher") {
            TextField("nom, brasserie, style…", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 7)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Theme.text)
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Admin sections

struct BeerAdminSub: View {
    let title: String
    var trailing: (() -> AnyView)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            if let trailing { trailing() }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct BeerAdminCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Boutons compacts (history-card__actions)

struct BeerCompactButton: View {
    let title: String
    var primary = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(primary ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Theme.card))
                .foregroundStyle(
                    primary ? Theme.btnPrimaryText : (destructive ? Theme.error : Theme.text)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(destructive ? Theme.error.opacity(0.45) : Theme.border)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct BeerLoadMoreButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.Font.btn, weight: .semibold))
                .frame(maxWidth: 280)
                .padding(.vertical, 13)
                .background(Theme.card)
                .foregroundStyle(Theme.text)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}

// MARK: - Panneau latéral (patch notes, IP invités)

struct BeerSidePanel<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: onClose) {
                    Text("×")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            ScrollView {
                content()
                    .padding(16)
            }
            BeerSecondaryButton(title: "Fermer", action: onClose)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Détail dégustation (detail-head)

struct BeerDetailHead: View {
    let onClose: () -> Void
    let onRetaste: () -> Void
    let onEdit: () -> Void
    var showHide: Bool = false
    var onHide: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            BeerGhostButton("Fermer", action: onClose)
            Spacer()
            if showHide, let onHide {
                BeerGhostButton("Masquer", action: onHide)
            }
            Button(action: onRetaste) {
                Text("Noter à nouveau")
                    .font(.system(size: Theme.Font.ghost, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.primaryGradient)
                    .foregroundStyle(Theme.btnPrimaryText)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
            }
            BeerGhostButton("Modifier", action: onEdit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bg)
    }
}