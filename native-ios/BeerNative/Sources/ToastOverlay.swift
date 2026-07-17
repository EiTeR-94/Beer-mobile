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

/// Bannière non-modale en haut d’écran — ne masque plus toute l’UI (plus de voile noir superposé).
struct ToastOverlay: View {
    let toast: ToastPayload?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let toast {
                ToastBanner(payload: toast, onDismiss: onDismiss)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(toast != nil)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: toast)
    }
}

private struct ToastBanner: View {
    let payload: ToastPayload
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                if let label = payload.label ?? defaultLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                }
                Text(payload.message)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = payload.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(Theme.bg.opacity(0.65))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bannerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .beerShadow(radius: 14, y: 6)
        .onTapGesture(perform: onDismiss)
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

    private var accent: Color {
        switch payload.variant {
        case .success: return Theme.ok
        case .info, .warn, .duplicate: return Theme.accent
        case .error: return Theme.error
        }
    }

    private var bannerBackground: some View {
        ZStack {
            Theme.card
            LinearGradient(
                colors: [accent.opacity(0.14), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
