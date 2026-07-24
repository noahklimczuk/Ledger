import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    // Bold-editorial display sizes for hero numbers and oversized headlines. Heavier and larger than
    // the standard scale so the numbers that matter carry the screen.
    static let appDisplay = AppFont.scaled(46, relativeTo: .largeTitle, weight: .heavy)
    static let appNumber = AppFont.scaled(30, relativeTo: .title, weight: .heavy)
}

// MARK: - Surfaces & spacing

enum Theme {
    /// Corner radii — one card radius everywhere so surfaces feel like one system. Bloom leans on
    /// large, soft radii for its tactile "clay" character.
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 15
    static let smallRadius: CGFloat = 10

    /// Vertical rhythm between stacked cards on a screen.
    static let sectionSpacing: CGFloat = 18
    /// Standard inner padding for a card.
    static let cardPadding: CGFloat = 18
}

extension Color {
    /// Clay's ground — a soft lilac in Day, a deep plum in Dusk — so clay cards read as raised,
    /// tactile surfaces above it.
    static let appBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.102, green: 0.090, blue: 0.145, alpha: 1)   // #1A1725
            : UIColor(red: 0.937, green: 0.929, blue: 0.984, alpha: 1)   // #EFEDFB
    })
    /// A raised card/surface — a cool near-white in Day, a lifted plum in Dusk.
    static let appSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.149, green: 0.133, blue: 0.200, alpha: 1)   // #262233
            : UIColor(red: 0.973, green: 0.965, blue: 1.000, alpha: 1)   // #F8F6FF
    })
    /// Hairline separators/borders tuned to be barely-there in both appearances.
    static let appHairline = Color.primary.opacity(0.06)
    /// Clay's soft drop shadow — a cool periwinkle-gray in Day, a deep shade in Dusk — the dark side
    /// of the two-shadow "clay" extrusion (cast down-right).
    static let bloomShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.55)
            : UIColor(red: 0.431, green: 0.392, blue: 0.667, alpha: 0.26)   // periwinkle-gray
    })
    /// The light side of the clay extrusion — a soft highlight cast up-left, so surfaces read as
    /// gently raised clay rather than flat cards. Barely-there in Dusk.
    static let bloomHighlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.05)
            : UIColor.white.withAlphaComponent(0.9)
    })
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
            // Two shadows make the "clay" extrusion: a cool dark cast down-right and a soft light
            // highlight up-left, so every surface reads as gently raised on the lilac ground.
            .shadow(color: Color.bloomShadow, radius: 18, y: 11)
            .shadow(color: Color.bloomHighlight, radius: 12, x: -7, y: -7)
    }
}
