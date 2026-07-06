import SwiftUI

struct InviteIPsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entries: [InviteIpEntry]

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("Aucune IP enregistrée").foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.ip ?? "—").font(.body.monospaced())
                            if let first = e.firstSeen {
                                Text("1re : \(BeerFormatters.formatDate(first))").font(.caption).foregroundStyle(Theme.muted)
                            }
                            if let last = e.lastSeen {
                                Text("Dernière : \(BeerFormatters.formatDate(last))").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}