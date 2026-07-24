import SwiftUI

extension Color {
    /// `brandEmerald` keeps the Bloom "good / complete" green for plan-status and success states.
    @MainActor static let brandEmerald = Color(red: 62 / 255, green: 158 / 255, blue: 110 / 255)  // #3E9E6E
    /// The main brand gradient now uses periwinkle blue, matching the requested app-wide accent.
    @MainActor static let brandPeriwinkle = Color(red: 142 / 255, green: 124 / 255, blue: 240 / 255)  // #8E7CF0
    @MainActor static let brandPeriwinkleDeep = Color(red: 111 / 255, green: 92 / 255, blue: 224 / 255)  // #6F5CE0
}

extension LinearGradient {
    /// The signature brand wash — now periwinkle blue to match the app's main accent.
    @MainActor static let brand = LinearGradient(
        colors: [.brandPeriwinkle, .brandPeriwinkleDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
