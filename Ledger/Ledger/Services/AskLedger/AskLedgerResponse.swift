import Foundation

/// Structured, on-device responses for Ask Ledger. Rather than plain paragraphs, the assistant
/// answers with a small set of composable "blocks" (a metric row, an insight, a chart, a forecast…)
/// so every answer reads like a briefing from a financial advisor, not a chat bubble. All of these
/// are plain value types with no view dependencies, so the engine can build them off the model layer
/// and the UI just renders them.

/// The emotional colour of a piece of an answer — mapped to a hue in the view layer.
nonisolated enum AskLedgerTone {
    case positive, neutral, caution, info
}

nonisolated struct AskLedgerMetric {
    let label: String
    let value: String
    var caption: String? = nil
    var tone: AskLedgerTone = .neutral
}

nonisolated struct AskLedgerInsightItem {
    let title: String
    let message: String
    let systemImage: String
    var tone: AskLedgerTone = .info
}

nonisolated struct AskLedgerBar {
    let label: String
    /// 0…1 relative height for the chart.
    let value: Double
    let valueText: String
    var isOver: Bool = false
}

nonisolated struct AskLedgerBudgetLine {
    let name: String
    let spentText: String
    let allocatedText: String
    let progress: Double
    let isOver: Bool
}

nonisolated struct AskLedgerSubLine {
    let name: String
    let amountText: String
    let cadence: String
    var flag: String? = nil
}

nonisolated struct AskLedgerForecastRow {
    let label: String
    let value: String
    var tone: AskLedgerTone = .neutral
}

nonisolated struct AskLedgerForecast {
    let headline: String
    let rows: [AskLedgerForecastRow]
    var tone: AskLedgerTone = .info
}

/// One renderable piece of an assistant answer.
nonisolated enum AskLedgerBlock {
    case paragraph(String)
    case headline(String)
    case metrics([AskLedgerMetric])
    case insight(AskLedgerInsightItem)
    case bars(title: String, bars: [AskLedgerBar])
    case budget(title: String, lines: [AskLedgerBudgetLine])
    case subscriptions(monthly: String, lines: [AskLedgerSubLine])
    case forecast(AskLedgerForecast)
    case progress(title: String, fraction: Double, caption: String, tone: AskLedgerTone)
}

/// A place Ask Ledger can take you when an answer suggests it. Limited to screens that are pushed
/// (not tab roots that manage their own navigation), so a jump never nests navigation stacks.
nonisolated enum AskLedgerRoute: Hashable {
    case analytics, subscriptions, goals, wellness
}

nonisolated enum AskLedgerActionKind {
    /// Ask a sharper follow-up question, staying in the conversation.
    case ask(String)
    /// Open a real screen in the app.
    case route(AskLedgerRoute)
}

/// A suggested action shown under an answer.
nonisolated struct AskLedgerAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let kind: AskLedgerActionKind
}

/// A full assistant answer: blocks to render, actions to offer, and follow-up questions to suggest.
nonisolated struct AskLedgerResponse {
    var blocks: [AskLedgerBlock] = []
    var actions: [AskLedgerAction] = []
    var followUps: [String] = []
}

nonisolated enum AskLedgerRole {
    case user, assistant
}

/// One turn in the conversation — a user question or an assistant answer (which may still be
/// "thinking" before its response lands).
nonisolated struct AskLedgerTurn: Identifiable {
    let id = UUID()
    let role: AskLedgerRole
    var text: String = ""
    var response: AskLedgerResponse? = nil
    var isThinking: Bool = false
}
