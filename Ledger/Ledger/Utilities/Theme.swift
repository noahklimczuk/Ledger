import SwiftUI

// MARK: - Typography

/// The app's typeface, bundled as a custom font. Swap `family` (and add the matching files — see
/// `Resources/Fonts/README.md`) to restyle the whole app's text in one place. Until the font files
/// are added to the target, `Font.custom` falls back to the system font automatically, so the app
/// still builds and runs — it just uses San Francisco until the files land.
enum AppFont {
    /// The font family / PostScript prefix. Change this one string to switch typeface app-wide.
    static let family = "Inter"

    /// A Dynamic-Type-scaled font in the app family at the given base size and weight.
    static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.custom(family, size: size, relativeTo: style).weight(weight)
    }
}

extension Font {
    // A tuned type scale in the app font. Sizes track the system text styles (and scale with Dynamic
    // Type via `relativeTo:`) but with slightly firmer weights for a more deliberate, professional feel.
    static let appLargeTitle = AppFont.scaled(34, relativeTo: .largeTitle, weight: .bold)
    static let appTitle = AppFont.scaled(28, relativeTo: .title, weight: .bold)
    static let appTitle2 = AppFont.scaled(22, relativeTo: .title2, weight: .semibold)
    static let appTitle3 = AppFont.scaled(20, relativeTo: .title3, weight: .semibold)
    static let appHeadline = AppFont.scaled(17, relativeTo: .headline, weight: .semibold)
    static let appBody = AppFont.scaled(17, relativeTo: .body, weight: .regular)
    static let appBodyMedium = AppFont.scaled(17, relativeTo: .body, weight: .medium)
    static let appCallout = AppFont.scaled(16, relativeTo: .callout, weight: .regular)
    static let appSubheadline = AppFont.scaled(15, relativeTo: .subheadline, weight: .regular)
    static let appFootnote = AppFont.scaled(13, relativeTo: .footnote, weight: .regular)
    static let appCaption = AppFont.scaled(12, relativeTo: .caption, weight: .medium)
    static let appCaption2 = AppFont.scaled(11, relativeTo: .caption2, weight: .medium)

    /// Large monetary figures — the same rounded, bold treatment used for headline balances.
    static let appMoney = AppFont.scaled(34, relativeTo: .largeTitle, weight: .bold)
}

// MARK: - Surfaces & spacing

enum Theme {
    /// Corner radii — one card radius everywhere so surfaces feel like one system.
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let smallRadius: CGFloat = 10

    /// Vertical rhythm between stacked cards on a screen.
    static let sectionSpacing: CGFloat = 18
    /// Standard inner padding for a card.
    static let cardPadding: CGFloat = 18
}

extension Color {
    /// The app's base background — a soft neutral so cards read as raised surfaces above it.
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    /// A raised card/surface color, adaptive for light and dark.
    static let appSurface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Hairline separators/borders tuned to be barely-there in both appearances.
    static let appHairline = Color.primary.opacity(0.06)
}

extension View {
    /// The app's standard card surface: a rounded, softly-shadowed panel with a hairline edge. Using
    /// one modifier everywhere keeps corner radius, fill, border, and shadow perfectly consistent.
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        self
            .padding(padding)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}
