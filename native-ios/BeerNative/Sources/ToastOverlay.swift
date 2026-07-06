import SwiftUI

struct ToastPayload: Equatable {
    enum Variant: Equatable {
        case success, info, warn, error, duplicate
    }

    let variant: Variant
    let message: String
    var detail: String?
    var label: String?
}

struct ToastOverlay: View {
    let toast: ToastPayload?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            if let toast {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture(perform: onDismiss)

                ToastCard(payload: toast)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .onTapGesture(perform: onDismiss)
            }
        }
        .animation(.easeOut(duration: 0.22), value: toast)
    }
}

private struct ToastCard: View {
    let payload: ToastPayload

    var body: some View {
        VStack(spacing: 0) {
            Text(icon)
                .font(.system(size: 24))
                .padding(.bottom, 4)

            if let label = payload.label ?? defaultLabel {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(labelColor)
            }

            Text(payload.message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            if let detail = payload.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.horizontal, -8)
                    }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: 360)
        .background(cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderColor))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .beerShadow(radius: 20, y: 10)
        .padding(.horizontal, 20)
    }

    private var icon: String {
        switch payload.variant {
        case .success: return "✓"
        case .info: return "ℹ︎"
        case .warn: return "!"
        case .error: return "✕"
        case .duplicate: return "🍺"
        }
    }

    private var defaultLabel: String? {
        switch payload.variant {
        case .success: return "Succès"
        case .info: return "Info"
        case .warn: return "Attention"
        case .error: return "Erreur"
        case .duplicate: return "Déjà dégustée"
        }
    }

    private var labelColor: Color {
        switch payload.variant {
        case .success: return Theme.ok
        case .info, .warn, .duplicate: return Theme.accent
        case .error: return Theme.error
        }
    }

    private var borderColor: Color {
        switch payload.variant {
        case .success: return Theme.ok.opacity(0.42)
        case .info, .warn, .duplicate: return Theme.accent.opacity(0.42)
        case .error: return Theme.error.opacity(0.42)
        }
    }

    private var cardBackground: LinearGradient {
        let tint: Color
        switch payload.variant {
        case .success: tint = Theme.ok
        case .info, .warn, .duplicate: tint = Theme.accent
        case .error: tint = Theme.error
        }
        return LinearGradient(
            colors: [tint.opacity(0.1), Theme.card],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}