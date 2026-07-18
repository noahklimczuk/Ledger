import SwiftUI

/// The redesign's playful, high-contrast palette. Each primary area of the app owns a signature hue
/// ("multi-accent by section"), so screens read as a colorful, mapped system while staying cohesive
/// through shared gradients, radii, and motion. Every hue is defined bright→deep so one accent yields
/// a solid tint, a soft wash, and a bold gradient.
nonisolated enum Palette {
    // Bright signature hues.
    static let emerald = Color(hex: "34D399")
    static let teal    = Color(hex: "14B8A6")
    static let sky     = Color(hex: "38BDF8")
    static let blue    = Color(hex: "3B82F6")
    static let indigo  = Color(hex: "6366F1")
    static let violet  = Color(hex: "8B5CF6")
    static let purple  = Color(hex: "A855F7")
    static let pink    = Color(hex: "EC4899")
    static let rose    = Color(hex: "F43F5E")
    static let orange  = Color(hex: "F97316")
    static let amber   = Color(hex: "F59E0B")
    static let cyan    = Color(hex: "06B6D4")
    static let lime    = Color(hex: "84CC16")

    // Deep companions, used as the far end of each accent gradient.
    static let emeraldDeep = Color(hex: "0E7C7B")
    static let blueDeep    = Color(hex: "2563EB")
    static let indigoDeep  = Color(hex: "4F46E5")
    static let violetDeep  = Color(hex: "7C3AED")
    static let pinkDeep    = Color(hex: "DB2777")
    static let roseDeep    = Color(hex: "E11D48")
    static let orangeDeep  = Color(hex: "EA580C")
    static let cyanDeep    = Color(hex: "0891B2")

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

    /// A soft, low-opacity fill of the hue for chips, icon badges, and tinted cards.
    var soft: Color { base.opacity(0.15) }

    /// Text/'glyph color that reads clearly on `soft`.
    var onSoft: Color { deep }

    // MARK: Section accents

    static let dashboard    = Accent(base: Color(hex: "3BD18F"), deep: Color(hex: "0E7C7B")) // brand emerald→teal
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

extension EnvironmentValues {
    /// The current screen's signature accent, so shared components (headers, buttons, chips) pick up
    /// the right hue without every call site passing it. Screens set it once at the top with
    /// `.accent(.transactions)` etc.
    @Entry var accent: Accent = .dashboard
}

extension View {
    /// Sets the screen's signature accent for everything below it in the hierarchy, and also tints
    /// SwiftUI's own controls (`.tint`) to match so system elements stay on-theme.
    func accent(_ accent: Accent) -> some View {
        environment(\.accent, accent).tint(accent.base)
    }
}
