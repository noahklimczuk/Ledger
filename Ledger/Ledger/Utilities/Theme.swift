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
    /// Bloom's ground — light lavender (Day) and deep midnight blue (Dusk) from the implementation plan.
    static let appBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.102, green: 0.090, blue: 0.146, alpha: 1)   // #1A1725
            : UIColor(red: 0.937, green: 0.929, blue: 0.984, alpha: 1)   // #EFEDFB
    })

    /// A raised card/surface — near-white (Day) and lifted midnight (Dusk) from the plan.
    static let appSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.149, green: 0.133, blue: 0.200, alpha: 1)   // #262233
            : UIColor(red: 0.973, green: 0.965, blue: 1.000, alpha: 1)   // #F8F6FF
    })

    /// The thin rim on clay cards. Uses the `--line` token: soft periwinkle (Day) / white (Dusk).
    static let appHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.09)
            : UIColor(red: 0.471, green: 0.431, blue: 0.706, alpha: 0.16)
    })

    /// Bloom's clay drop shadow — neutral black at the plan's `ClayCard` opacity.
    static let bloomShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.55)
            : UIColor.black.withAlphaComponent(0.12)
    })

    /// Bloom's clay top highlight — white in Day, a whisper in Dusk (`--sl`).
    static let bloomHighlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.045)
            : UIColor.white.withAlphaComponent(0.70)
    })

    /// A secondary raised surface used for small icon chips and inset fields (`--surf2`).
    static let appSurface2 = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.125, green: 0.114, blue: 0.173, alpha: 1)   // #201D2C
            : UIColor(red: 0.937, green: 0.925, blue: 0.988, alpha: 1)   // #EFECFC
    })

    /// Bloom's primary text color (`--ink`): dark slate in Day, soft white in Dusk.
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.945, green: 0.937, blue: 0.973, alpha: 1)   // #F1EFF8
            : UIColor(red: 0.173, green: 0.165, blue: 0.267, alpha: 1)   // #2C2A44
    })

    /// Bloom's secondary text color (`--ink2`): muted purple in Day, dim lavender in Dusk.
    static let ink2 = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.678, green: 0.651, blue: 0.753, alpha: 1)   // #ADA6C0
            : UIColor(red: 0.420, green: 0.408, blue: 0.522, alpha: 1)   // #6B6885
    })

    /// Bloom's tertiary text color (`--ink3`): soft lavender in Day, deeper muted in Dusk.
    static let ink3 = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.459, green: 0.431, blue: 0.549, alpha: 1)   // #756E8C
            : UIColor(red: 0.635, green: 0.612, blue: 0.753, alpha: 1)   // #A29CC0
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

// MARK: - Mesh/radial background

/// The Bloom page background from `bloom-mobile.html`: a warm base plus two soft radial
/// glows — top-trailing amber/peach and bottom-leading green. It ignores safe areas so the
/// gradient sits under the navigation bar and tab bar.
struct BloomBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = max(proxy.size.width, proxy.size.height)
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()
                // Top-trailing amber/peach glow
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Palette.peach.opacity(0.22), location: 0),
                        .init(color: Palette.amber.opacity(0.10), location: 0.5),
                        .init(color: Color.clear, location: 1.0)
                    ]),
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: size * 0.65
                )
                .offset(x: size * 0.15, y: -size * 0.15)
                // Bottom-leading green glow
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Palette.emerald.opacity(0.14), location: 0),
                        .init(color: Palette.emerald.opacity(0.05), location: 0.55),
                        .init(color: Color.clear, location: 1.0)
                    ]),
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: size * 0.55
                )
                .offset(x: -size * 0.10, y: size * 0.10)
            }
            .ignoresSafeArea()
        }
    }
}
