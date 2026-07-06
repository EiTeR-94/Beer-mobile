import SwiftUI

enum Theme {
    static let bg = Color(red: 0.06, green: 0.08, blue: 0.10)
    static let card = Color(red: 0.10, green: 0.13, blue: 0.17)
    static let accent = Color(red: 0.79, green: 0.64, blue: 0.15)
    static let text = Color(red: 0.89, green: 0.91, blue: 0.94)
    static let muted = Color(red: 0.58, green: 0.64, blue: 0.72)
    static let border = Color.white.opacity(0.08)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func beerCard() -> some View { modifier(CardStyle()) }
}