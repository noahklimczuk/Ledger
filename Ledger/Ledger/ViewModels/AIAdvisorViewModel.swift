import Foundation
import Observation
import SwiftData

/// Drives the floating "Financial Advisor" chat on the Budgets screen. It builds a snapshot of
/// the current month's plan, recent spending averages, and recent transactions once when the chat
/// starts, hands that to Gemini as the system instruction, and then relays a normal back-and-
/// forth conversation. The advisor can also *act*: when asked to build a budget it calls the
/// `create_budget` tool and this view model writes the month's budgets — including a savings
/// set-aside proportional to the gap between income and spending.
///
/// Privacy matches the budget-suggestion feature: budget totals and transaction lines (date,
/// amount, category, merchant) are sent — never account names, balances, notes, or receipts.
/// The advisor is conversational guidance, not licensed financial advice.
@MainActor
@Observable
final class AIAdvisorViewModel {
    struct Message: Identifiable {
        enum Role { case user, assistant }
        enum Kind { case text, actionNote }
        let id = UUID()
        let role: Role
        var kind: Kind = .text
        var text: String
    }

    private(set) var messages: [Message] = []
    private(set) var isSending = false
    private(set) var errorText: String?

    /// Starter questions offered before the user has typed anything.
    let suggestedPrompts = [
        "Create a budget for me this month",
        "How am I doing this month?",
        "Where can I cut back?",
    ]

    var apiKeyText: String = ""
    /// Stored (not computed off the Keychain) so the view reacts when a key is saved and swaps the
    /// key-entry screen for the chat.
    private(set) var hasAPIKey: Bool
    var hasStarted: Bool { !messages.isEmpty }

    let month: Date
    private let modelContext: ModelContext
    private var systemInstruction: String?
    /// The full API-side conversation, including function-call round trips that never render as
    /// chat bubbles. Kept separate from `messages` (the UI transcript) for exactly that reason.
    private var apiHistory: [GeminiService.ChatTurn] = []

    /// How many `create_budget` rounds one message may trigger — guards against a call loop.
    private static let maxToolRoundsPerSend = 2

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

        errorText = nil
        messages.append(Message(role: .user, text: text))
        apiHistory.append(.user(text))

        // Build the snapshot lazily on the first message so it reflects the latest edits.
        let system = systemInstruction ?? buildSystemInstruction()
        systemInstruction = system

        isSending = true
        defer { isSending = false }

        do {
            var toolRounds = 0
            while true {
                let reply = try await GeminiService().advise(system: system, history: apiHistory, apiKey: apiKey)
                let replyText = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !replyText.isEmpty {
                    messages.append(Message(role: .assistant, text: replyText))
                }

                guard let plan = reply.budgetPlan, toolRounds < Self.maxToolRoundsPerSend else {
                    if !replyText.isEmpty {
                        apiHistory.append(.model(text: replyText, functionCall: nil))
                    }
                    break
                }
                toolRounds += 1

                apiHistory.append(.model(
                    text: replyText.isEmpty ? nil : replyText,
                    functionCall: GeminiService.FunctionCallEcho(
                        name: GeminiService.createBudgetToolName,
                        argsJSON: reply.budgetPlanArgsJSON ?? "{}"
                    )
                ))
                let result = applyBudgetPlan(plan)
                messages.append(Message(role: .assistant, kind: .actionNote, text: result.note))
                apiHistory.append(.functionResponse(
                    name: GeminiService.createBudgetToolName,
                    responseJSON: result.responseJSON
                ))
                // The plan changed the data the snapshot was built from; rebuild it next message.
                systemInstruction = nil
            }
        } catch {
            // Leave the user's question in the transcript and surface why it failed; they can retry.
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Applying a budget plan

    /// Writes the model's `create_budget` plan as this month's budgets: named categories are
    /// matched case-insensitively against the user's expense categories, and the savings amount
    /// lands on a (created-if-needed) "Savings" category. Returns a chat-facing note and the JSON
    /// result handed back to the model.
    private func applyBudgetPlan(_ plan: GeminiService.BudgetPlan) -> (note: String, responseJSON: String) {
        let budgets = BudgetsViewModel(modelContext: modelContext)
        budgets.selectedMonth = month

        let expenseCategories = ((try? modelContext.fetch(FetchDescriptor<Category>())) ?? [])
            .filter { !$0.isIncome && !$0.isTransfer }
        var byName: [String: Category] = [:]
        for category in expenseCategories { byName[category.name.lowercased()] = category }

        func existingRollover(for category: Category) -> Bool {
            budgets.rows
                .first { $0.budget.category?.persistentModelID == category.persistentModelID }?
                .budget.rolloverEnabled ?? false
        }

        var applied = 0
        var skipped: [String] = []
        for item in plan.categories {
            let key = item.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let category = byName[key] else {
                skipped.append(item.name)
                continue
            }
            budgets.addOrUpdateBudget(
                category: category,
                allocatedAmount: Self.roundedToDollar(item.amount),
                rolloverEnabled: existingRollover(for: category)
            )
            applied += 1
        }

        var savingsSet: Decimal = 0
        if plan.savingsAmount > 0 {
            let savingsCategory = budgets.findOrCreateSavingsCategory()
            savingsSet = Self.roundedToDollar(plan.savingsAmount)
            budgets.addOrUpdateBudget(
                category: savingsCategory,
                allocatedAmount: savingsSet,
                rolloverEnabled: existingRollover(for: savingsCategory)
            )
            applied += 1
        }

        var note = "Budget applied — \(applied) categor\(applied == 1 ? "y" : "ies") set for \(DateFormatting.monthYear(month))"
        if savingsSet > 0 { note += ", including \(CurrencyFormatter.string(from: savingsSet)) to savings" }
        note += "."

        var response: [String: Any] = ["status": "applied", "budgetsSet": applied]
        if savingsSet > 0 { response["savingsBudgeted"] = (savingsSet as NSDecimalNumber).doubleValue }
        if !skipped.isEmpty { response["skippedUnknownCategories"] = skipped }
        let responseJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            responseJSON = String(decoding: data, as: UTF8.self)
        } else {
            responseJSON = #"{"status":"applied"}"#
        }
        return (note, responseJSON)
    }

    // MARK: - Context

    /// The advisor persona plus a snapshot of the user's finances: this month's plan, recent
    /// per-category averages, recent transactions, and the ground rules for `create_budget`.
    private func buildSystemInstruction() -> String {
        let budgets = BudgetsViewModel(modelContext: modelContext)
        budgets.selectedMonth = month
        budgets.load()

        let history = BudgetSuggestionService(modelContext: modelContext).summarize(before: month)

        var lines: [String] = []
        lines.append("You are a friendly, practical personal financial advisor built into a Canadian budgeting app called Ledger. All amounts are Canadian dollars (CAD).")
        lines.append("")
        lines.append("Guidelines: Give specific, actionable advice grounded in the numbers below. Be concise — short paragraphs and tight bullet lists, not essays. Reference the user's actual categories, amounts, and transactions. You are not a licensed financial professional: avoid firm tax, legal, or investment guarantees, and suggest a professional for major decisions. If a question needs data you don't have, say what you'd need.")
        lines.append("")
        lines.append("Creating budgets: when — and only when — the user asks you to create, set, or update their budget, call the \(GeminiService.createBudgetToolName) tool; it applies to \(DateFormatting.monthYear(month)). Base the amounts on the transaction history below and use the exact category names listed. Always include savingsAmount, sized in proportion to the gap between the month's income and spending: when income comfortably exceeds spending, direct most of the surplus to savings; when the budget is tight, keep it small or zero. Category budgets plus savings must stay within monthly income. Savings is budgeted automatically under a \"Savings\" category — don't also list it in categories.")

        let expenseCategoryNames = ((try? modelContext.fetch(FetchDescriptor<Category>())) ?? [])
            .filter { !$0.isIncome && !$0.isTransfer }
            .map(\.name)
            .sorted()
        if !expenseCategoryNames.isEmpty {
            lines.append("Expense categories available for budgeting: \(expenseCategoryNames.joined(separator: ", ")).")
        }

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

        let transactionLines = recentTransactionLines()
        if !transactionLines.isEmpty {
            lines.append("")
            lines.append("=== Recent transactions (this month and the 3 before it, most recent first) ===")
            lines.append("Format: date | amount (negative = money out) | category | merchant")
            lines.append(contentsOf: transactionLines)
        }

        return lines.joined(separator: "\n")
    }

    /// Transactions for the selected month plus the three before it, as compact prompt lines.
    private func recentTransactionLines() -> [String] {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(byAdding: .month, value: -3, to: month),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: month) else { return [] }
        let transactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
            .filter { $0.date >= windowStart && $0.date < monthEnd }
        return BudgetSuggestionService.promptLines(
            for: transactions,
            limit: BudgetSuggestionService.promptTransactionLimit
        )
    }

    private func money(_ value: Decimal) -> String {
        CurrencyFormatter.string(from: value)
    }

    private static func roundedToDollar(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
