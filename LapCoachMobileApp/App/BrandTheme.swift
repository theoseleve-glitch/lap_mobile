import SwiftUI

enum BrandTheme {
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let surface = Color.white
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.22)
    static let muted = Color(red: 0.41, green: 0.47, blue: 0.54)
    static let accent = Color(red: 0.05, green: 0.58, blue: 0.54)
    static let accentWarm = Color(red: 0.92, green: 0.43, blue: 0.22)
    static let success = Color(red: 0.18, green: 0.63, blue: 0.38)
    static let warning = Color(red: 0.91, green: 0.62, blue: 0.18)
    static let danger = Color(red: 0.82, green: 0.22, blue: 0.18)
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.19, blue: 0.28),
            Color(red: 0.07, green: 0.46, blue: 0.51),
            Color(red: 0.95, green: 0.48, blue: 0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(BrandTheme.surface)
                    .shadow(color: Color.black.opacity(0.07), radius: 22, x: 0, y: 10)
            )
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}
