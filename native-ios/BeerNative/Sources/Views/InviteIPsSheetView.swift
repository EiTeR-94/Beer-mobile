import SwiftUI

struct InviteIPsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entries: [InviteIpEntry]

    var body: some View {
        BeerSidePanel(title: title, onClose: { dismiss() }) {
            if entries.isEmpty {
                Text("Aucune IP enregistrée")
                    .font(.system(size: Theme.Font.lead * 0.94))
                    .foregroundStyle(Theme.muted)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.ip ?? "—")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Theme.text)
                            if let first = e.firstSeen {
                                Text("1re : \(BeerFormatters.formatDate(first))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.muted)
                            }
                            if let last = e.lastSeen {
                                Text("Dernière : \(BeerFormatters.formatDate(last))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}