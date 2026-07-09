import SwiftUI

extension Color {
    /// Brand palette, matched to the app icon (emerald → teal).
    @MainActor static let brandEmerald = Color(red: 59 / 255, green: 209 / 255, blue: 143 / 255)
    @MainActor static let brandTeal = Color(red: 14 / 255, green: 124 / 255, blue: 123 / 255)
}

extension LinearGradient {
    /// The signature emerald→teal wash used on the launch screen and hero surfaces.
    @MainActor static let brand = LinearGradient(
        colors: [.brandEmerald, .brandTeal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
