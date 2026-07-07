import SwiftUI

struct PatchnotesSheetView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var version = ""

    var body: some View {
        BeerSidePanel(
            title: "Patch notes \(version.isEmpty ? "" : "v\(version)")",
            onClose: { dismiss() }
        ) {
            Text(text.isEmpty ? "Chargement…" : text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if let p = try? await app.api.patchnotes() {
                version = p.version ?? app.serverVersion
                text = p.markdown ?? ""
            }
        }
    }
}