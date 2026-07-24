import SwiftUI

extension Color {
    /// Bloom (Clay) brand hues — periwinkle into soft peach, matching the mockup wordmark. Used
    /// behind the logo, on the splash, and on hero marks. (The logo image itself is left unchanged.)
    /// `brandEmerald` also serves as the "good / complete" mark in a few places, so it stays a solid
    /// Clay periwinkle — the name is historic; the hue is periwinkle.
    @MainActor static let brandEmerald = Color(red: 139 / 255, green: 123 / 255, blue: 240 / 255)  // #8B7BF0
    @MainActor static let brandPeach = Color(red: 255 / 255, green: 159 / 255, blue: 136 / 255)    // #FF9F88
}

extension LinearGradient {
    /// The signature periwinkle→peach Clay wash used on the launch screen and hero surfaces.
    @MainActor static let brand = LinearGradient(
        colors: [.brandEmerald, .brandPeach],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
