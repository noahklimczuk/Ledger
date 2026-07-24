import SwiftUI

/// Bloom (Clay palette) — the app's calm, wellness-forward system. One periwinkle-led family instead
/// of a dozen loud hues: **periwinkle** is the primary — brand, wellness, income and every positive
/// state — with a cool **mint** companion for accounts and growth, a soft **peach** for spending
/// energy, and a warm **coral** for debt / over-budget. (Amber is gone; it folds into peach.) Each
/// area still owns a signature `Accent`, but they harmonize into one periwinkle system on the lilac
/// (Day) / plum (Dusk) grounds defined in `Theme`. Every hue is bright→deep so one accent yields a
/// solid tint, a soft wash, and a bold gradient.
///
/// Note on naming: `green` is Clay's primary and holds **periwinkle** (matching the mockups, where
/// `--green` is the periwinkle token). Keeping the historic property names lets every existing call
/// site inherit the Clay recolor without a sweep.
nonisolated enum Palette {
    // Periwinkle — Clay's primary: brand, wellness, income, and all positive states.
    static let green       = Color(hex: "8B7BF0")
    static let greenDeep   = Color(hex: "6F5CE0")
    static let greenBright = Color(hex: "A99BFF")
    // Mint companion — accounts and growth.
    static let teal        = Color(hex: "39B98A")
    static let tealDeep    = Color(hex: "2E9E77")
    // Peach — spending energy (amber folds in here).
    static let peach       = Color(hex: "FF9F88")
    static let peachDeep   = Color(hex: "F2704F")
    static let amber       = Color(hex: "FF9F88")
    static let amberDeep   = Color(hex: "F2704F")
    // Periwinkle — Ask Ledger / analytical (same family as the primary).
    static let peri        = Color(hex: "8B7BF0")
    static let periDeep    = Color(hex: "6F5CE0")
    // Coral — debt / over-budget.
    static let coral       = Color(hex: "FF6F6F")
    static let coralDeep   = Color(hex: "E85B5B")

    // Back-compat aliases: earlier call sites refer to these names directly. Mapping them into the
    // Clay family means every screen inherits the palette without a call-site sweep, and any future
    // reference stays on-theme automatically.
    static let emerald     = green
    static let emeraldDeep = greenDeep
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
    static let lime        = greenBright

    // Shared money semantics used on every screen, so income/expense read the same everywhere.
    // In Clay, positive money is periwinkle (the primary) and over/negative is coral.
    static let income  = green
    static let expense = coral
}

/// A section's signature color kit: a base hue, a deep companion, and everything derived from them —
/// the bold gradient behind hero cards, a soft wash for tinted surfaces, and the on-gradient text
/// color. Screens pick an `Accent` (Dashboard = periwinkle, Accounts = mint, Budgets = peach, …)
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

    /// A soft fill of the hue for chips, icon badges, and tinted cards. Kept clearly colored on the
    /// lilac ground rather than a barely-there gray.
    var soft: Color { base.opacity(0.22) }

    /// Text/glyph color that reads clearly on `soft`.
    var onSoft: Color { deep }

    // MARK: Section accents — all within the Clay periwinkle family.

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
    /// Financial Wellness — Bloom's heart, in periwinkle.
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
