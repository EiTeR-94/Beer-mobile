import SwiftUI

struct TutorialStep {
    let icon: String
    let title: String
    let text: String
}

let beerTutorialSteps: [TutorialStep] = [
    TutorialStep(
        icon: "🍺",
        title: "Bienvenue sur Beer Log",
        text: "Garde une trace de toutes tes dégustations : quelques secondes suffisent pour scanner, noter et te souvenir de tes bières préférées."
    ),
    TutorialStep(
        icon: "📷",
        title: "1. Trouve ta bière",
        text: "Scanne le code-barres, ou cherche-la sur Untappd (brasserie + nom). Rien trouvé ? La saisie manuelle est toujours là en secours."
    ),
    TutorialStep(
        icon: "📸",
        title: "2. Photo & lieu",
        text: "Ajoute une photo du verre et le lieu de dégustation si tu veux — tout est optionnel, tu peux passer directement à la note."
    ),
    TutorialStep(
        icon: "⭐",
        title: "3. Note & ressenti",
        text: "Glisse le curseur pour la note, choisis les goûts et les houblons qui correspondent, ajoute un petit commentaire si l'envie te prend."
    ),
    TutorialStep(
        icon: "📜",
        title: "Retrouve tout",
        text: "Historique, Galerie photos et recherche : tu retombes toujours sur tes dégustations passées en 2 clics."
    ),
    TutorialStep(
        icon: "🍺🎁",
        title: "À boire & idées cadeaux",
        text: "Ta liste « À boire » garde tes envies de côté. « Idées cadeaux » suggère des bières à offrir selon vos notes à tous les deux."
    ),
    TutorialStep(
        icon: "📖",
        title: "Le Grimoire Beerquest",
        text: "Chaque dégustation te fait gagner de l'XP, débloque des quêtes et des badges. Si le jeu est actif pour toi, retrouve tout ça dans le Grimoire."
    ),
    TutorialStep(
        icon: "✅",
        title: "C'est tout !",
        text: "Tu es prêt·e. Ce tutoriel reste accessible à tout moment depuis Mon compte → Tutoriel."
    ),
]

struct TutorialSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    var onClose: () -> Void = {}

    private var step: TutorialStep { beerTutorialSteps[index] }
    private var isLast: Bool { index == beerTutorialSteps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comment ça marche")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(action: { dismiss() }) {
                    Text("×")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Text(step.icon)
                    .font(.system(size: 52))
                Text(step.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                Text(step.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(beerTutorialSteps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.accent : Theme.border)
                        .frame(width: i == index ? 20 : 6, height: 6)
                        .animation(.easeOut(duration: 0.15), value: index)
                }
            }
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                if index > 0 {
                    BeerGhostButton("← Précédent") { index -= 1 }
                }
                Button(action: {
                    if isLast { dismiss() } else { index += 1 }
                }) {
                    Text(isLast ? "Compris !" : "Suivant →")
                        .font(.system(size: Theme.Font.btn, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 16)
                        .background(Theme.primaryGradient)
                        .foregroundStyle(Theme.btnPrimaryText)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onDisappear { onClose() }
    }
}
