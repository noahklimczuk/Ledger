import SwiftUI

/// The redesign's playful, high-contrast palette. Each primary area of the app owns a signature hue
/// ("multi-accent by section"), so screens read as a colorful, mapped system while staying cohesive
/// through shared gradients, radii, and motion. Every hue is defined bright→deep so one accent yields
/// a solid tint, a soft wash, and a bold gradient.
nonisolated enum Palette {
    // Bright signature hues — punched up a notch past Tailwind-500 for a more vivid, saturated look.
    static let emerald = Color(hex: "05D68C")
    static let teal    = Color(hex: "06C2AE")
    static let sky     = Color(hex: "1FB4FF")
    static let blue    = Color(hex: "2E6DFF")
    static let indigo  = Color(hex: "5B5CF7")
    static let violet  = Color(hex: "8E3BFF")
    static let purple  = Color(hex: "B23BFF")
    static let pink    = Color(hex: "FF3D96")
    static let rose    = Color(hex: "FF2D55")
    static let orange  = Color(hex: "FF6A00")
    static let amber   = Color(hex: "FFA400")
    static let cyan    = Color(hex: "06C9E8")
    static let lime    = Color(hex: "8CE00C")

    // Deep companions, used as the far end of each accent gradient — kept rich and saturated so the
    // hero gradients read boldly rather than fading to a muddy dark.
    static let emeraldDeep = Color(hex: "01997C")
    static let blueDeep    = Color(hex: "2E5BFF")
    static let indigoDeep  = Color(hex: "4B3BF0")
    static let violetDeep  = Color(hex: "7A1FFF")
    static let pinkDeep    = Color(hex: "E4157F")
    static let roseDeep    = Color(hex: "F5003C")
    static let orangeDeep  = Color(hex: "F94A00")
    static let cyanDeep    = Color(hex: "0499C4")

    // Shared money semantics used on every screen, so income/expense read the same everywhere.
    static let income  = emerald
    static let expense = rose
}

/// A section's signature color kit: a base hue, a deep companion, and everything derived from them —
/// the bold gradient behind hero cards, a soft wash for tinted surfaces, and the on-gradient text
/// color. Screens pick an `Accent` (Dashboard = brand, Transactions = violet, Budgets = orange, …)
/// and draw all of their color from it, so each area feels distinct but is built the same way.
nonisolated struct Accent: Equatable {
    let base: Color
    let deep: Color

    /// The bold diagonal gradient used on hero cards, primary buttons, and selected states.
    var gradient: LinearGradient {
        LinearGradient(colors: [base, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A subtle same-direction wash for large tinted fills.
    var faintGradient: LinearGradient {
        LinearGradient(colors: [base.opacity(0.16), deep.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A soft fill of the hue for chips, icon badges, and tinted cards. Kept fairly strong so tinted
    /// surfaces read as clearly colored rather than a barely-there gray.
    var soft: Color { base.opacity(0.24) }

    /// Text/'glyph color that reads clearly on `soft`.
    var onSoft: Color { deep }

    // MARK: Section accents

    static let dashboard    = Accent(base: Color(hex: "1FDD97"), deep: Color(hex: "05A07E")) // brand emerald→teal, brighter
    static let accounts     = Accent(base: Palette.sky,    deep: Palette.blueDeep)
    static let transactions = Accent(base: Palette.violet, deep: Palette.violetDeep)
    static let budgets      = Accent(base: Palette.amber,  deep: Palette.orangeDeep)
    static let reports      = Accent(base: Palette.indigo, deep: Palette.indigoDeep)
    static let goals        = Accent(base: Palette.emerald, deep: Palette.emeraldDeep)
    static let debt         = Accent(base: Palette.rose,   deep: Palette.roseDeep)
    static let bills        = Accent(base: Palette.cyan,   deep: Palette.cyanDeep)
    static let recurring    = Accent(base: Palette.pink,   deep: Palette.pinkDeep)
    static let insights     = Accent(base: Palette.purple, deep: Palette.violetDeep)
    static let checkIn      = Accent(base: Palette.orange, deep: Palette.orangeDeep)
    static let categories   = Accent(base: Palette.blue,   deep: Palette.indigoDeep)
}

nonisolated private struct AccentEnvironmentKey: EnvironmentKey {
    static let defaultValue: Accent = .dashboard
}

extension EnvironmentValues {
    /// The current screen's signature accent, so shared components (headers, buttons, chips) pick up
    /// the right hue without every call site passing it. Screens set it once at the top with
    /// `.accent(.transactions)` etc.
    nonisolated var accent: Accent {
        get { self[AccentEnvironmentKey.self] }
        set { self[AccentEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Sets the screen's signature accent for everything below it in the hierarchy, and also tints
    /// SwiftUI's own controls (`.tint`) to match so system elements stay on-theme.
    func accent(_ accent: Accent) -> some View {
        environment(\.accent, accent).tint(accent.base)
    }
}
