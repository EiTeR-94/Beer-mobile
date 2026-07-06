import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0f1419)
    static let card = Color(hex: 0x1a222c)
    static let text = Color(hex: 0xf1f5f9)
    static let muted = Color(hex: 0x94a3b8)
    static let accent = Color(hex: 0xf59e0b)
    static let accent2 = Color(hex: 0xd97706)
    static let ok = Color(hex: 0x34d399)
    static let border = Color(hex: 0x2d3a4a)
    static let star = Color(hex: 0xfbbf24)
    static let starOff = Color(hex: 0x475569)
    static let photoBg = Color(hex: 0x0a0a0c)
    static let btnPrimaryText = Color(hex: 0x1a1208)
    static let error = Color(hex: 0xf87171)

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
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