import SwiftUI

// MARK: - Pending — extrait de MainView.swift

struct PendingSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Créations en attente") {
                    if app.pendingItems.isEmpty {
                        Text("Aucune dégustation en attente.")
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(app.pendingItems) { pending in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pending.beerName)
                                    .font(.headline)
                                Text("\(pending.brewery) · \(pending.style) · ★\(String(format: "%.1f", pending.rating))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                                if !pending.comment.isEmpty {
                                    Text(pending.comment)
                                        .font(.caption)
                                }
                                Text(pending.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    app.removePending(id: pending.id)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                Section("Suppressions en attente") {
                    if app.pendingDeletes.isEmpty {
                        Text("Aucune suppression en attente.")
                            .foregroundStyle(Theme.muted)
                    } else {
                        ForEach(app.pendingDeletes, id: \.self) { delId in
                            HStack {
                                Text("Suppression #\(delId)")
                                Spacer()
                                Text("en file")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    app.removePendingDelete(id: delId)
                                } label: {
                                    Label("Annuler", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("En attente (\(app.pendingCount))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Synchroniser") {
                        Task {
                            await app.syncPending()
                            dismiss()
                        }
                    }
                    .disabled(app.pendingCount == 0)
                }
            }
        }
    }
}
