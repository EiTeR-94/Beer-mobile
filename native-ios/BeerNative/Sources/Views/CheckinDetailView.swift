import SwiftUI

struct CheckinDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: CheckinItem
    let onRetaste: () -> Void
    let onEdit: () -> Void
    var onUpdated: (() -> Void)?

    @State private var hidden: Bool
    @State private var toggling = false

    init(item: CheckinItem, onRetaste: @escaping () -> Void, onEdit: @escaping () -> Void, onUpdated: (() -> Void)? = nil) {
        self.item = item
        self.onRetaste = onRetaste
        self.onEdit = onEdit
        self.onUpdated = onUpdated
        _hidden = State(initialValue: item.hiddenFromPartner == true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if item.photoURL != nil {
                        BeerImage(path: item.photoURL)
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text("Pas de photo")
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .foregroundStyle(Theme.muted)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text(item.beerName).font(.title2.bold())
                    Text("\(item.brewery ?? "—") · \(item.style ?? "?") · \(BeerFormatters.formatDate(item.createdAt))")
                        .font(.subheadline).foregroundStyle(Theme.muted)

                    HStack {
                        Text("★★★★★").foregroundStyle(Theme.starOff)
                            .overlay(alignment: .leading) {
                                Text("★★★★★").foregroundStyle(Theme.star)
                                    .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(item.rating, totalWidth: 80)) }
                            }
                        Text(BeerFormatters.ratingLabel(item.rating)).foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }

                    if let flavors = item.flavors, !flavors.isEmpty {
                        Text("Goûts : \(flavors.joined(separator: ", "))").font(.footnote)
                    }
                    if let hops = item.hops, !hops.isEmpty {
                        Text("Houblons : \(hops.joined(separator: ", "))").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if let comment = item.comment, !comment.isEmpty {
                        Text("« \(comment) »").italic().padding().beerCard()
                    }

                    if app.isAdmin {
                        Button(toggling ? "…" : (hidden ? "Rendre visible" : "Masquer")) {
                            Task { await toggleHidden() }
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    }

                    BeerPrimaryButton(title: "Noter à nouveau") { onRetaste(); dismiss() }
                    BeerSecondaryButton(title: "Modifier") { onEdit() }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Détail")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func toggleHidden() async {
        toggling = true
        defer { toggling = false }
        do {
            hidden.toggle()
            try await app.api.updateCheckin(
                id: item.id,
                rating: nil,
                flavors: nil,
                hops: nil,
                comment: nil,
                hiddenFromPartner: hidden
            )
            onUpdated?()
        } catch {
            hidden.toggle()
        }
    }
}