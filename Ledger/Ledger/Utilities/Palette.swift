import SwiftUI

/// Bloom — the app's warm, wellness-forward palette. One calm family instead of a dozen loud hues:
/// living **periwinkle** for the brand/wellness accent, warm **peach/amber** for spending energy,
/// periwinkle for Ask Ledger and analytics, and a soft **coral** for debt / over-budget. Each area still owns a
/// signature `Accent`, but they harmonize into a single warm system on the ivory (Day) / plum (Dusk)
/// grounds defined in `Theme`. Every hue is bright→deep so one accent yields a solid tint, a soft
/// wash, and a bold gradient.
nonisolated enum Palette {
    // Living periwinkle — the brand / wellness hue.
    static let green       = Color(hex: "8E7CF0")
    static let greenDeep   = Color(hex: "6F5CE0")
    static let greenBright = Color(hex: "A89AF4")
    // Teal-green companion (accounts).
    static let teal        = Color(hex: "2FA69A")
    static let tealDeep    = Color(hex: "1F7B72")
    // Warm spending energy.
    static let peach       = Color(hex: "FF8F6B")
    static let peachDeep   = Color(hex: "EF5F3D")
    static let amber       = Color(hex: "FFB15C")
    static let amberDeep   = Color(hex: "F2894A")
    // Periwinkle — Ask Ledger / analytical.
    static let peri        = Color(hex: "8E7CF0")
    static let periDeep    = Color(hex: "6F5CE0")
    // Coral — debt / over-budget.
    static let coral       = Color(hex: "EF5F3D")
    static let coralDeep   = Color(hex: "C9463C")

    // Back-compat aliases: earlier call sites refer to these names directly. Mapping them into the
    // Bloom family means every screen inherits the new palette without a call-site sweep, and any
    // future reference stays on-theme automatically.
    static let emerald     = Color(hex: "3E9E6E")
    static let emeraldDeep = Color(hex: "2F7B54")
    static let sky         = teal
    static let blue        = peri
    static let blueDeep    = periDeep
    static let indigo      = peri
    static let indigoDeep  = periDeep
    static let violet      = peri
    static let violetDeep  = periDeep
    static let purple      = peri
    static let pink        = peach
    static let pinkDeep    = peachDeep
    static let rose        = coral
    static let roseDeep    = coralDeep
    static let orange      = amber
    static let orangeDeep  = amberDeep
    static let cyan        = teal
    static let cyanDeep    = tealDeep
    static let lime        = Color(hex: "57C88A")

    // Shared money semantics used on every screen, so income/expense read the same everywhere.
    static let income  = Color(hex: "3E9E6E")
    static let expense = coral
}

/// A section's signature color kit: a base hue, a deep companion, and everything derived from them —
/// the bold gradient behind hero cards, a soft wash for tinted surfaces, and the on-gradient text
/// color. Screens pick an `Accent` (Dashboard = periwinkle, Transactions = periwinkle, Budgets = amber, …)
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

    /// A soft fill of the hue for chips, icon badges, and tinted cards. Kept warm and clearly colored
    /// on the ivory ground rather than a barely-there gray.
    var soft: Color { base.opacity(0.22) }

    /// Text/glyph color that reads clearly on `soft`.
    var onSoft: Color { deep }

    // MARK: Section accents — all within the Bloom family.

    static let dashboard    = Accent(base: Palette.green,  deep: Palette.greenDeep)
    static let accounts     = Accent(base: Palette.teal,   deep: Palette.tealDeep)
    static let transactions = Accent(base: Palette.peri,   deep: Palette.periDeep)
    static let budgets      = Accent(base: Palette.amber,  deep: Palette.peachDeep)
    static let reports      = Accent(base: Palette.peri,   deep: Palette.periDeep)
    static let goals        = Accent(base: Palette.green,  deep: Palette.greenDeep)
    static let debt         = Accent(base: Palette.coral,  deep: Palette.coralDeep)
    static let bills        = Accent(base: Palette.amber,  deep: Palette.amberDeep)
    static let recurring    = Accent(base: Palette.peach,  deep: Palette.peachDeep)
    static let insights     = Accent(base: Palette.peri,   deep: Palette.periDeep)
    static let checkIn      = Accent(base: Palette.green,  deep: Palette.greenDeep)
    static let categories   = Accent(base: Palette.peri,   deep: Palette.periDeep)
    /// Financial Wellness — Bloom's heart, in the brand periwinkle accent.
    static let wellness     = Accent(base: Palette.green,  deep: Palette.greenDeep)
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
