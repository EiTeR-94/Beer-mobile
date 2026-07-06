import SwiftUI

struct CheckinDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: CheckinItem
    let onRetaste: () -> Void
    let onEdit: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BeerImage(path: item.photoURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

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
}