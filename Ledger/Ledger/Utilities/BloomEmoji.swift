import Foundation
import SwiftData
import SwiftUI

/// Maps Ledger's default category, account, and merchant names to the emoji icons used in the
/// `bloom-ios.html` rendering. Falls back to a sensible default for anything not in the map so
/// user-defined items still get a readable icon.
nonisolated enum BloomEmoji {
    nonisolated static func categoryEmoji(name: String) -> String {
        switch name.lowercased() {
        case "salary", "paycheque", "paycheck", "income": return "💵"
        case "interest": return "📈"
        case "refunds", "reimbursement", "tax refund": return "🔄"
        case "groceries", "grocery": return "🛒"
        case "restaurants", "dining", "restaurant": return "🍽️"
        case "coffee": return "☕"
        case "gas", "fuel": return "⛽"
        case "transit", "transport", "transportation": return "🚊"
        case "rideshare", "uber", "lyft": return "🚗"
        case "rent", "housing": return "🏠"
        case "utilities", "hydro", "internet", "phone & internet": return "⚡"
        case "insurance": return "🛡️"
        case "health", "pharmacy", "medical": return "⚕️"
        case "subscriptions", "subscription", "netflix", "spotify", "apple music", "apple tv", "icloud": return "🔄"
        case "shopping", "clothing": return "🛍️"
        case "entertainment", "movies", "games": return "🎬"
        case "fitness", "gym": return "🏋️"
        case "travel", "vacation", "flights": return "✈️"
        case "fees", "bank fee", "service charge": return "💳"
        case "fun", "discretionary": return "🎉"
        case "savings", "emergency fund": return "💰"
        default: return "💰"
        }
    }

    nonisolated static func accountEmoji(institution: String?, type: String?) -> String {
        let name = (institution ?? "").lowercased()
        switch name {
        case let n where n.contains("wealthsimple"): return "🍁"
        case let n where n.contains("rbc"): return "🏦"
        case let n where n.contains("td"): return "🏦"
        case let n where n.contains("scotia"): return "🏦"
        case let n where n.contains("bmo"): return "🏦"
        case let n where n.contains("cibc"): return "🏦"
        case let n where n.contains("tangerine"): return "🏦"
        case let n where n.contains("simplii"): return "🏦"
        case let n where n.contains("eq"): return "🏦"
        case let n where n.contains("visa"): return "💳"
        case let n where n.contains("mastercard"): return "💳"
        case let n where n.contains("amex"), let n where n.contains("american express"): return "💳"
        default:
            switch (type ?? "").lowercased() {
            case "savings": return "💰"
            case "credit": return "💳"
            case "investment", "retirement": return "📈"
            default: return "🏦"
            }
        }
    }

    nonisolated static func merchantEmoji(name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("loblaws") || lower.contains("grocery") || lower.contains("metro") || lower.contains("sobeys") || lower.contains("costco") {
            return "🛒"
        }
        if lower.contains("starbucks") || lower.contains("tim hortons") || lower.contains("coffee") {
            return "☕"
        }
        if lower.contains("netflix") { return "🎬" }
        if lower.contains("spotify") { return "🎵" }
        if lower.contains("apple music") || lower.contains("apple com bill") { return "🎵" }
        if lower.contains("gym") || lower.contains("goodlife") || lower.contains("fitness") { return "🏋️" }
        if lower.contains("icloud") { return "☁️" }
        if lower.contains("uber") || lower.contains("lyft") { return "🚗" }
        if lower.contains("restaurant") || lower.contains("mcdonald") || lower.contains("doordash") || lower.contains("uber eats") { return "🍽️" }
        if lower.contains("gas") || lower.contains("shell") || lower.contains("esso") { return "⛽" }
        if lower.contains("pharmacy") || lower.contains("shoppers") || lower.contains("rexall") { return "⚕️" }
        if lower.contains("airline") || lower.contains("air canada") || lower.contains("westjet") || lower.contains("flight") { return "✈️" }
        if lower.contains("amazon") || lower.contains("shopping") { return "🛍️" }
        return "💰"
    }

    nonisolated static func recurringEmoji(name: String) -> String {
        merchantEmoji(name: name)
    }

    nonisolated static func goalEmoji(name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("emerg") { return "🌳" }
        if lower.contains("japan") || lower.contains("travel") || lower.contains("vacation") { return "🌿" }
        if lower.contains("laptop") || lower.contains("tech") || lower.contains("computer") { return "🌱" }
        return "🎯"
    }
}

// MARK: - Model extensions

nonisolated extension Category {
    var bloomEmoji: String { BloomEmoji.categoryEmoji(name: name) }
    /// The icon the app should render for this category. Bloom uses emoji icons in the rendering.
    var displayIcon: String { bloomEmoji }
}

nonisolated extension Account {
    var bloomEmoji: String { BloomEmoji.accountEmoji(institution: institutionName, type: type.rawValue) }
    var displayIcon: String { bloomEmoji }
}

nonisolated extension RecurringSeries {
    var bloomEmoji: String { BloomEmoji.recurringEmoji(name: displayName) }
    var displayIcon: String { bloomEmoji }
}

nonisolated extension Insight {
    var displayIcon: String {
        switch systemImage {
        case "chart.line.uptrend.xyaxis", "arrow.up.right.circle": return "📈"
        case "exclamationmark.triangle.fill", "creditcard.trianglebadge.exclamationmark": return "⚠️"
        case "doc.on.doc": return "📑"
        case "arrow.triangle.2.circlepath": return "🔄"
        case "arrow.down.right.circle": return "📉"
        default: return "✨"
        }
    }
}

nonisolated extension DebtKind {
    var displayIcon: String {
        switch self {
        case .creditCard, .lineOfCredit, .other: return "💳"
        case .studentLoan: return "🎓"
        case .carLoan: return "🚗"
        case .mortgage: return "🏠"
        case .personalLoan: return "👤"
        }
    }
}

// MARK: - Row icon

/// The 44pt rounded emoji icon used in account and subscription rows, matching the `.row .ic` style
/// in `bloom-ios.html`: `var(--surf2)` background, 14pt radius, small clay shadow.
struct BloomRowIcon: View {
    let emoji: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.41))
            .frame(width: size, height: size)
            .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
            .shadow(color: Color.bloomShadow, radius: 5, x: 4, y: 4)
            .shadow(color: Color.bloomHighlight, radius: 4, x: -3, y: -3)
            .accessibilityHidden(true)
    }
}
