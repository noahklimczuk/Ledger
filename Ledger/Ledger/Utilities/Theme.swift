import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Appearance

/// The app's explicit appearance override. Stored in `UserDefaults` via `@AppStorage` and applied at
/// the root with `.preferredColorScheme`. Defaults to `system` so the device setting wins until the
/// user flips the Day/Dusk toggle.
enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Day"
        case .dark:   return "Dusk"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

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

    /// Large monetary figures — transaction hero amounts, matching the rendering's `.txhero .a` (44pt).
    static let appMoney = AppFont.scaled(44, relativeTo: .largeTitle, weight: .bold)

    // Bold-editorial display sizes for hero numbers and oversized headlines. Heavier and larger than
    // the standard scale so the numbers that matter carry the screen. Sizes track the Bloom CSS:
    // `.amtbig` 56pt for headline balances, `.onbh` 30pt for prominent metrics.
    static let appDisplay = AppFont.scaled(56, relativeTo: .largeTitle, weight: .heavy)
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
    /// Bloom's ground — the warm ivory (Day) and plum-charcoal (Dusk) from `bloom-ios.html`.
    static let appBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.126, green: 0.106, blue: 0.130, alpha: 1)   // #201B21
            : UIColor(red: 0.945, green: 0.922, blue: 0.890, alpha: 1)   // #F1EBE3
    })

    /// A raised card/surface — warm off-white (Day) and lifted plum (Dusk) from `bloom-ios.html`.
    static let appSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.141, blue: 0.173, alpha: 1)   // #2A242C
            : UIColor(red: 0.984, green: 0.969, blue: 0.945, alpha: 1)   // #FBF7F1
    })

    /// The thin rim on clay cards. In Day it is a white 50% stroke, in Dusk it is a barely-there
    /// white 2.25% stroke (`color-mix(--sl 50%, transparent)` from the CSS).
    static let appHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.025)
            : UIColor.white.withAlphaComponent(0.50)
    })

    /// Bloom's clay drop shadow — warm brown in Day, deep black in Dusk (`--sd`).
    static let bloomShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.55)
            : UIColor(red: 0.588, green: 0.471, blue: 0.373, alpha: 0.30)
    })

    /// Bloom's clay top highlight — white in Day, a whisper in Dusk (`--sl`).
    static let bloomHighlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.045)
            : UIColor.white.withAlphaComponent(1.0)
    })

    /// A secondary raised surface used for the small emoji icons in rows (`--surf2`).
    static let appSurface2 = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.141, green: 0.122, blue: 0.149, alpha: 1)   // #241F26
            : UIColor(red: 0.957, green: 0.933, blue: 0.902, alpha: 1)   // #F4EEE6
    })
}

extension View {
    /// A clay card matching the Bloom CSS exactly: a rounded surface, a 1px inset rim, a warm
    /// down-right shadow, and a soft up-left highlight. Every card in the app uses this so the
    /// tactile "Bloom" feel is identical on every screen.
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        self
            .padding(padding)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
            // Bloom CSS `.clay` shadow: 7px 7px 20px var(--sd), -6px -6px 14px var(--sl).
            .shadow(color: Color.bloomShadow, radius: 20, x: 7, y: 7)
            .shadow(color: Color.bloomHighlight, radius: 14, x: -6, y: -6)
    }
}
