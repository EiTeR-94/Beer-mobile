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
        VStack(spacing: 0) {
            BeerDetailHead(
                onClose: { dismiss() },
                onRetaste: { onRetaste(); dismiss() },
                onEdit: { dismiss(); onEdit() },
                showHide: app.isAdmin,
                onHide: app.isAdmin ? { Task { await toggleHidden() } } : nil
            )

            ScrollView {
                VStack(spacing: 14) {
                    Group {
                        if item.photoURL != nil {
                            BeerImage(path: item.photoURL)
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 320)
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                        } else {
                            Text("Pas de photo")
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                                .foregroundStyle(Theme.muted)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.beerName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                        if app.isAdmin, item.hiddenFromPartner == true {
                            BeerPrivateBadge()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.brewery ?? "—") · \(item.style ?? "?") · \(BeerFormatters.formatDate(item.createdAt))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let loc = item.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                        locationRow(loc)
                    }

                    HStack(spacing: 6) {
                        Text("★★★★★").foregroundStyle(Theme.starOff)
                            .overlay(alignment: .leading) {
                                Text("★★★★★").foregroundStyle(Theme.star)
                                    .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(item.rating, totalWidth: 80)) }
                            }
                        Text(BeerFormatters.ratingLabel(item.rating))
                            .foregroundStyle(Theme.accent)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let flavors = item.flavors, !flavors.isEmpty {
                        Text("Goûts : \(flavors.joined(separator: ", "))")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let hops = item.hops, !hops.isEmpty {
                        Text("Houblons : \(hops.joined(separator: ", "))")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let comment = item.comment, !comment.isEmpty {
                        Text("« \(comment) »")
                            .italic()
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.text)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func locationRow(_ loc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("📍")
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lieu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(loc)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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