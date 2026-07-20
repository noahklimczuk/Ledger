import SwiftUI

extension Color {
    /// Bloom brand hues — living green into warm peach. Used behind the logo, on the splash, and on
    /// hero marks. (The logo image itself is left unchanged.) `brandEmerald` also serves as the
    /// "good / complete" green in a few places, so it stays a solid Bloom green.
    @MainActor static let brandEmerald = Color(red: 62 / 255, green: 158 / 255, blue: 110 / 255)  // #3E9E6E
    @MainActor static let brandPeach = Color(red: 255 / 255, green: 143 / 255, blue: 107 / 255)   // #FF8F6B
}

extension LinearGradient {
    /// The signature green→peach Bloom wash used on the launch screen and hero surfaces.
    @MainActor static let brand = LinearGradient(
        colors: [.brandEmerald, .brandPeach],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
