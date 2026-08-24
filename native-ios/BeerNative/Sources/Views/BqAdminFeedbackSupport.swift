import SwiftUI

struct UserKey: Identifiable {
    let id: String
}

struct FeedbackResolveTarget: Identifiable {
    let id: Int
    let status: String
    let title: String
    let hint: String
    let requireReply: Bool
    let original: String
}

struct FeedbackResolveSheet: View {
    let target: FeedbackResolveTarget
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var reply = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(target.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(target.hint)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if !target.original.isEmpty {
                    Text("« \(String(target.original.prefix(180)))\(target.original.count > 180 ? "…" : "") »")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .italic()
                }
                Text(target.requireReply ? "Raison (obligatoire)" : "Message pour le joueur (optionnel)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                TextEditor(text: $reply)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.text)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(Theme.fieldBg)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button("Annuler", action: onCancel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    Button {
                        onSubmit(reply.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Text("Envoyer")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.07))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(LinearGradient(colors: [Theme.accent, Color.orange], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(target.requireReply && reply.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .opacity(target.requireReply && reply.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.5 : 1)
                }
            }
            .padding(16)
            .background(Theme.bg)
        }
    }
}

