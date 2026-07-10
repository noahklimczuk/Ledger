import Foundation
import Observation
import SwiftData

/// Drives the floating "Financial Advisor" chat on the Budgets screen. It builds a compact,
/// **aggregated** snapshot of the current month's plan and recent spending averages once when the
/// chat opens, hands that to Gemini as the system instruction, and then relays a normal back-and-
/// forth conversation.
///
/// Privacy matches the budget-suggestion feature: only aggregated numbers (category budgets/spend,
/// income, recurring totals) are ever sent — never raw transactions, merchants, account names, or
/// balances. The advisor is conversational guidance, not licensed financial advice.
@MainActor
@Observable
final class AIAdvisorViewModel {
    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    private(set) var messages: [Message] = []
    var input: String = ""
    private(set) var isSending = false
    private(set) var errorText: String?

    /// Starter questions offered before the user has typed anything.
    let suggestedPrompts = [
        "How am I doing this month?",
        "Where can I cut back?",
        "Am I on track with my budget?",
    ]

    var apiKeyText: String = ""
    /// Stored (not computed off the Keychain) so the view reacts when a key is saved and swaps the
    /// key-entry screen for the chat.
    private(set) var hasAPIKey: Bool
    var hasStarted: Bool { !messages.isEmpty }

    let month: Date
    private let modelContext: ModelContext
    private var systemInstruction: String?

    init(modelContext: ModelContext, month: Date) {
        self.modelContext = modelContext
        self.month = Budget.normalize(month)
        self.hasAPIKey = GeminiService.storedAPIKey != nil
    }

    func saveAPIKey() {
        GeminiService.setAPIKey(apiKeyText)
        apiKeyText = ""
        hasAPIKey = GeminiService.storedAPIKey != nil
    }

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard let apiKey = GeminiService.storedAPIKey else {
            errorText = "Add your free Google Gemini API key first."
            return
        }

        input = ""
        errorText = nil
        messages.append(Message(role: .user, text: text))

        // Build the aggregated snapshot lazily on the first message so it reflects the latest edits.
        let system = systemInstruction ?? buildSystemInstruction()
        systemInstruction = system

        isSending = true
        defer { isSending = false }

        let history = messages.map { message in
            GeminiService.ChatTurn(
                role: message.role == .user ? .user : .model,
                text: message.text
            )
        }

        do {
            let reply = try await GeminiService().advise(system: system, history: history, apiKey: apiKey)
            messages.append(Message(role: .assistant, text: reply))
        } catch {
            // Leave the user's question in the transcript and surface why it failed; they can retry.
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Context

    /// The advisor persona plus a compact, aggregated snapshot of the user's finances. Kept small
    /// on purpose — enough for grounded advice, nothing transaction-level.
    private func buildSystemInstruction() -> String {
        let budgets = BudgetsViewModel(modelContext: modelContext)
        budgets.selectedMonth = month
        budgets.load()

        let history = BudgetSuggestionService(modelContext: modelContext).summarize(before: month)

        var lines: [String] = []
        lines.append("You are a friendly, practical personal financial advisor built into a Canadian budgeting app called Ledger. All amounts are Canadian dollars (CAD).")
        lines.append("")
        lines.append("Guidelines: Give specific, actionable advice grounded in the numbers below. Be concise — short paragraphs and tight bullet lists, not essays. Reference the user's actual categories and amounts. You are not a licensed financial professional: avoid firm tax, legal, or investment guarantees, and suggest a professional for major decisions. If a question needs data you don't have, say what you'd need. You only ever see these aggregated figures — never individual transactions — so don't claim to see specific purchases.")
        lines.append("")
        lines.append("=== \(DateFormatting.monthYear(month)) plan ===")
        lines.append("Income to assign: \(money(budgets.incomeToAssign))")
        lines.append("Assigned to categories: \(money(budgets.totalAllocated)) (left to assign: \(money(budgets.leftToAssign)))")
        lines.append("Spent so far: \(money(budgets.totalSpent)) of \(money(budgets.totalAvailable)) available (remaining: \(money(budgets.totalRemaining)))")
        lines.append("Month elapsed: \(Int((budgets.monthProgress * 100).rounded()))%")

        if budgets.rows.isEmpty {
            lines.append("No category budgets have been set for this month yet.")
        } else {
            lines.append("")
            lines.append("Category budgets this month (budgeted / spent / remaining):")
            for row in budgets.rows {
                let name = row.budget.category?.name ?? "Uncategorized"
                lines.append("- \(name): \(money(row.allocatedIncludingRollover)) / \(money(row.spent)) / \(money(row.remaining))")
            }
        }

        if !budgets.unbudgeted.isEmpty {
            lines.append("")
            lines.append("Spending with no budget this month:")
            for row in budgets.unbudgeted {
                lines.append("- \(row.category?.name ?? "Uncategorized"): \(money(row.spent))")
            }
        }

        if let history {
            lines.append("")
            lines.append("Recent history (last \(history.months) months):")
            lines.append("Average monthly income: \(money(history.averageMonthlyIncome)); monthly recurring commitments: \(money(history.monthlyRecurringCommitments))")
            lines.append("Average monthly spend by category (recent-half average in brackets):")
            for stat in history.stats {
                lines.append("- \(stat.category.name): \(money(stat.average)) (\(money(stat.recentAverage)))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func money(_ value: Decimal) -> String {
        CurrencyFormatter.string(from: value)
    }
}
