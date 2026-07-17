import SwiftUI

/// Petite fenêtre admin : dégustations + commentaires d'un invité.
struct InviteCheckinsSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let invite: InviteItem

    @State private var items: [CheckinItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: CheckinItem?

    private var title: String {
        let name = invite.label ?? invite.username ?? "Invité"
        let n = invite.checkins ?? items.count
        return "\(name) · \(n) dégust."
    }

    var body: some View {
        BeerSidePanel(title: title, onClose: { dismiss() }) {
            if loading && items.isEmpty {
                ProgressView("Chargement…")
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let error, items.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if items.isEmpty {
                BeerEmptyState(
                    icon: "🍺",
                    title: "Aucune dégustation",
                    subtitle: invite.redeemedAt == nil
                        ? "L'invitation n'a pas encore été utilisée."
                        : "Cet invité n'a encore rien noté."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            selected = item
                        } label: {
                            checkinRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $selected) { item in
            CheckinDetailView(
                item: item,
                onRetaste: { selected = nil },
                onEdit: { selected = nil }
            )
            .environmentObject(app)
            .beerSheetChrome()
        }
    }

    private func checkinRow(_ item: CheckinItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if item.photoURL != nil {
                        BeerImage(path: item.photoURL)
                            .frame(width: 64, height: 64)
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.bg)
                            .frame(width: 64, height: 64)
                            .overlay(Text("🍺").font(.title3))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.beerName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text("★★★★★").font(.system(size: 10)).foregroundStyle(Theme.starOff)
                            .overlay(alignment: .leading) {
                                Text("★★★★★").font(.system(size: 10)).foregroundStyle(Theme.star)
                                    .mask { Rectangle().frame(width: BeerFormatters.starFillWidth(item.rating, totalWidth: 55)) }
                            }
                        Text(BeerFormatters.ratingLabel(item.rating))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text("\(item.brewery ?? "—") · \(item.style ?? "?") · \(BeerFormatters.formatDate(item.createdAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    if let loc = item.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                        Text("📍 \(loc)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let flavors = item.flavors, !flavors.isEmpty {
                Text(flavors.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            if let hops = item.hops, !hops.isEmpty {
                Text("Houblons : \(hops.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            if let comment = item.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                Text("« \(comment) »")
                    .font(.system(size: 13).italic())
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            items = try await app.api.adminInviteCheckins(inviteId: invite.id, limit: 50, offset: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
