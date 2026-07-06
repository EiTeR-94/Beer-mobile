import SwiftUI

struct PatchnotesSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var version = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "Chargement…" : text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Patch notes v\(version)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task {
                if let p = try? await app.api.patchnotes() {
                    version = p.version ?? app.serverVersion
                    text = p.markdown ?? ""
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}