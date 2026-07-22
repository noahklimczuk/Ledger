import Foundation
import Observation
import SwiftData

/// Drives the floating Ask Ledger chat. It builds a snapshot of
/// the current month's plan, recent spending averages, and recent transactions once when the chat
/// starts, hands that to Gemini as the system instruction, and then relays a normal back-and-
/// forth conversation. Ask Ledger can also *act*: when asked to build a budget it calls the
/// `create_budget` tool and this view model writes the month's budgets — including a savings
/// set-aside proportional to the gap between income and spending.
///
/// Privacy matches the budget-suggestion feature: budget totals and transaction lines (date,
/// amount, category, merchant) are sent — never account names, balances, notes, or receipts.
/// The advisor is conversational guidance, not licensed financial advice.
@MainActor
@Observable
final class AskLedgerViewModel {
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

    /// The chat being viewed and appended to. Created lazily on the first message so empty chats
    /// never pile up; `nil` means a fresh, not-yet-saved conversation.
    private var currentChat: AdvisorChat?
    /// Saved conversations for the history menu, most-recently-updated first.
    private(set) var recentChats: [AdvisorChat] = []

    /// How many `create_budget` rounds one message may trigger — guards against a call loop.
    private static let maxToolRoundsPerSend = 2
    /// Cap on how many past chats the history menu lists.
    private static let recentChatLimit = 25

    init(modelContext: ModelContext, month: Date) {
        self.modelContext = modelContext
        self.month = Budget.normalize(month)
        self.hasAPIKey = GeminiService.storedAPIKey != nil
        loadMostRecentChat()
    }

    // MARK: - Saved chats

    /// Opens the most recent saved conversation on launch so the advisor resumes where it left off.
    private func loadMostRecentChat() {
        refreshRecentChats()
        if let chat = recentChats.first { restore(chat) }
    }

    /// Starts a fresh conversation, leaving the current one saved. The next message creates its
    /// record, so tapping New Chat repeatedly never leaves empty chats behind.
    func newChat() {
        currentChat = nil
        messages = []
        apiHistory = []
        systemInstruction = nil
        errorText = nil
        refreshRecentChats()
    }

    /// Reopens a saved conversation from the history menu.
    func openChat(_ chat: AdvisorChat) {
        errorText = nil
        restore(chat)
    }

    private func refreshRecentChats() {
        var descriptor = FetchDescriptor<AdvisorChat>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = Self.recentChatLimit
        recentChats = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Loads a saved chat into the live transcript and rebuilds the API history from it. Only the
    /// visible text turns are replayed to the model — action notes are UI-only records of a past
    /// budget change, and the freshly built system snapshot already reflects those budgets.
    private func restore(_ chat: AdvisorChat) {
        currentChat = chat
        let ordered = chat.orderedMessages
        messages = ordered.map { record in
            Message(
                role: record.role == "user" ? .user : .assistant,
                kind: record.kind == "actionNote" ? .actionNote : .text,
                text: record.text
            )
        }
        apiHistory = ordered.compactMap { record -> GeminiService.ChatTurn? in
            switch (record.role, record.kind) {
            case ("user", _): return .user(record.text)
            case ("assistant", "text"): return .model(text: record.text, functionCall: nil, thoughtSignature: nil)
            default: return nil
            }
        }
        // Rebuild the snapshot for the currently open month on the next message.
        systemInstruction = nil
    }

    /// Appends a message to the live transcript and persists it, creating the chat on the first
    /// message so an unsent conversation never gets saved.
    private func appendMessage(_ message: Message) {
        messages.append(message)

        let chat: AdvisorChat
        if let existing = currentChat {
            chat = existing
        } else {
            let created = AdvisorChat(month: month)
            modelContext.insert(created)
            currentChat = created
            chat = created
        }

        let record = AdvisorChatMessage(
            role: message.role == .user ? "user" : "assistant",
            kind: message.kind == .actionNote ? "actionNote" : "text",
            text: message.text,
            sortIndex: chat.messages.count
        )
        modelContext.insert(record)
        record.chat = chat
        chat.updatedAt = .now
        // Title the chat from its first user message so the history list is scannable.
        if message.role == .user, chat.title == "New Chat" {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chat.title = String(trimmed.prefix(60)) }
        }
        try? modelContext.save()
        refreshRecentChats()
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
        appendMessage(Message(role: .user, text: text))
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
                    appendMessage(Message(role: .assistant, text: replyText))
                }

                guard toolRounds < Self.maxToolRoundsPerSend else {
                    if !replyText.isEmpty {
                        apiHistory.append(.model(text: replyText, functionCall: nil, thoughtSignature: reply.thoughtSignature))
                    }
                    break
                }

                if let plan = reply.budgetPlan {
                    toolRounds += 1

                    apiHistory.append(.model(
                        text: replyText.isEmpty ? nil : replyText,
                        functionCall: GeminiService.FunctionCallEcho(
                            name: GeminiService.createBudgetToolName,
                            argsJSON: reply.budgetPlanArgsJSON ?? "{}"
                        ),
                        // Echo Gemini's reasoning token back on the function-call part next request, or
                        // the follow-up round-trip 400s with "missing a thought_signature".
                        thoughtSignature: reply.thoughtSignature
                    ))
                    let result = applyBudgetPlan(plan)
                    appendMessage(Message(role: .assistant, kind: .actionNote, text: result.note))
                    apiHistory.append(.functionResponse(
                        name: GeminiService.createBudgetToolName,
                        responseJSON: result.responseJSON
                    ))
                    // The plan changed the data the snapshot was built from; rebuild it next message.
                    systemInstruction = nil
                } else if let deletePlan = reply.deletePlan {
                    toolRounds += 1

                    apiHistory.append(.model(
                        text: replyText.isEmpty ? nil : replyText,
                        functionCall: GeminiService.FunctionCallEcho(
                            name: GeminiService.deleteBudgetToolName,
                            argsJSON: reply.deletePlanArgsJSON ?? "{}"
                        ),
                        thoughtSignature: reply.thoughtSignature
                    ))
                    let result = applyDeletePlan(deletePlan)
                    appendMessage(Message(role: .assistant, kind: .actionNote, text: result.note))
                    apiHistory.append(.functionResponse(
                        name: GeminiService.deleteBudgetToolName,
                        responseJSON: result.responseJSON
                    ))
                    systemInstruction = nil
                } else {
                    if !replyText.isEmpty {
                        apiHistory.append(.model(text: replyText, functionCall: nil, thoughtSignature: reply.thoughtSignature))
                    }
                    break
                }
            }
        } catch {
            // Leave the user's question in the transcript and surface why it failed; they can retry.
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Applying a budget plan

    /// Writes the model's `create_budget` plan as budgets for one month — or, for a vague
    /// range request, every month the plan spans. Named categories are matched case-insensitively
    /// against the user's expense categories, and the savings amount lands on a (created-if-needed)
    /// "Savings" category. Returns a chat-facing note and the JSON result handed back to the model.
    private func applyBudgetPlan(_ plan: GeminiService.BudgetPlan) -> (note: String, responseJSON: String) {
        // A plan can target the open month, another single month, or a range of months the user
        // asked to budget together ("the next three months", "January through March"). The same
        // amounts apply to each month in the resolved set.
        let targetMonths = resolveMonths(plan)

        let expenseCategories = ((try? modelContext.fetch(FetchDescriptor<Category>())) ?? [])
            .filter { !$0.isIncome && !$0.isTransfer }
        var byName: [String: Category] = [:]
        for category in expenseCategories { byName[category.name.lowercased()] = category }

        // Per-month counts are identical (same plan, same categories), so keep the last iteration's.
        var appliedPerMonth = 0
        var savingsSet: Decimal = 0
        var skipped: [String] = []
        for targetMonth in targetMonths {
            let result = applyPlan(plan, to: targetMonth, categoriesByName: byName)
            appliedPerMonth = result.applied
            savingsSet = result.savingsSet
            skipped = result.skipped
        }

        let monthsLabel = Self.monthsLabel(targetMonths)
        var note = "Budget applied — \(appliedPerMonth) categor\(appliedPerMonth == 1 ? "y" : "ies") set for \(monthsLabel)"
        if savingsSet > 0 { note += ", including \(CurrencyFormatter.string(from: savingsSet)) to savings\(targetMonths.count > 1 ? " each month" : "")" }
        note += "."

        var response: [String: Any] = [
            "status": "applied",
            "budgetsSetPerMonth": appliedPerMonth,
            "months": targetMonths.map(Self.monthKey)
        ]
        if savingsSet > 0 { response["savingsBudgetedPerMonth"] = (savingsSet as NSDecimalNumber).doubleValue }
        if !skipped.isEmpty { response["skippedUnknownCategories"] = skipped }
        let responseJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            responseJSON = String(decoding: data, as: UTF8.self)
        } else {
            responseJSON = #"{"status":"applied"}"#
        }
        return (note, responseJSON)
    }

    /// Applies the plan's amounts to a single month. Returns how many categories were set (including
    /// savings), the savings amount, and any category names that didn't match one of the user's.
    private func applyPlan(
        _ plan: GeminiService.BudgetPlan,
        to targetMonth: Date,
        categoriesByName byName: [String: Category]
    ) -> (applied: Int, savingsSet: Decimal, skipped: [String]) {
        let budgets = BudgetsViewModel(modelContext: modelContext)
        budgets.selectedMonth = targetMonth

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

        return (applied, savingsSet, skipped)
    }

    /// Applies the model's `delete_budget` call by removing budgets for the requested month and
    /// optionally a single category. Returns a chat-facing note and the JSON result handed back.
    private func applyDeletePlan(_ plan: GeminiService.BudgetDeletion) -> (note: String, responseJSON: String) {
        let targetMonth = parseMonth(plan.month) ?? month
        let budgets = (try? modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.month == targetMonth }))) ?? []
        let searchName = plan.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetLower = searchName?.lowercased()

        var deleted = 0
        for budget in budgets {
            if let targetLower {
                guard let category = budget.category else { continue }
                if category.name.trimmingCharacters(in: .whitespaces).lowercased() == targetLower {
                    modelContext.delete(budget)
                    deleted += 1
                }
            } else {
                modelContext.delete(budget)
                deleted += 1
            }
        }
        try? modelContext.save()
        systemInstruction = nil

        let monthLabel = DateFormatting.monthYear(targetMonth)
        let note: String
        if deleted > 0 {
            note = targetLower != nil
                ? "Deleted \(deleted) budget(s) for \(monthLabel) matching '\(searchName!)'."
                : "Deleted all \(deleted) budgets for \(monthLabel)."
        } else {
            note = "No matching budgets found for \(monthLabel)."
        }

        let response: [String: Any] = [
            "status": deleted > 0 ? "deleted" : "no_match",
            "deleted": deleted,
            "month": Self.monthKey(targetMonth)
        ]
        let responseJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: response) {
            responseJSON = String(decoding: data, as: UTF8.self)
        } else {
            responseJSON = #"{"status":"no_match"}"#
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
        lines.append("You are Ask Ledger, a friendly, practical personal finance assistant built into a Canadian budgeting app called Ledger. All amounts are Canadian dollars (CAD).")
        lines.append("")
        lines.append("Guidelines: Give specific, actionable advice grounded in the numbers below. Be concise — short paragraphs and tight bullet lists, not essays. Reference the user's actual categories, amounts, and transactions. You are not a licensed financial professional: avoid firm tax, legal, or investment guarantees, and suggest a professional for major decisions. If a question needs data you don't have, say what you'd need.")
        lines.append("")
        lines.append("Today is \(DateFormatting.medium(.now)). The month currently open in the app is \(DateFormatting.monthYear(month)) (\(Self.monthKey(month))).")
        lines.append("Creating budgets: when — and only when — the user asks you to create, set, or update their budget, call the \(GeminiService.createBudgetToolName) tool. It defaults to the open month (\(DateFormatting.monthYear(month))), but you can budget any month — past or future — by passing the `month` argument as \"YYYY-MM\". For vague or multi-month requests like \"the next three months\", \"the rest of the year\", or \"January through March\", pass `startMonth` and `endMonth` (both \"YYYY-MM\", inclusive) instead and the same amounts apply to every month in that range. Resolve relative phrases like \"last month\", \"next month\", or \"the next three months\" against today's date above; if a request is ambiguous about the span, make a sensible interpretation and state which months you set. Base the amounts on the transaction history below and use the exact category names listed. Always include savingsAmount, sized in proportion to the gap between the month's income and spending: when income comfortably exceeds spending, direct most of the surplus to savings; when the budget is tight, keep it small or zero. Category budgets plus savings must stay within monthly income. Savings is budgeted automatically under a \"Savings\" category — don't also list it in categories.")
        lines.append("Deleting budgets: when the user asks to delete, remove, or clear a budget or the whole month's plan, call the \(GeminiService.deleteBudgetToolName) tool. Pass `month` as \"YYYY-MM\" for the month to target (defaults to the open month), and optionally `categoryName` to remove only that category's budget. Omit `categoryName` to delete every budget for the month. Do not call this tool unless the user explicitly asks to delete a budget.")

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

        let incomeLines = monthlyIncomeLines()
        if !incomeLines.isEmpty {
            lines.append("")
            lines.append("Actual income received per month (money in, excluding transfers between accounts):")
            lines.append(contentsOf: incomeLines)
            lines.append("Use a specific month's actual income when budgeting that month; fall back to the recent average only for months with no figure here (e.g. future months).")
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

    /// Actual income for each recent month (up to 12, oldest first), so the advisor can budget a
    /// given month against what really came in that month rather than only a running average.
    /// Income mirrors the Budgets tab: positive, non-archived transactions that are uncategorized or
    /// in an income category — which excludes transfers between the user's own accounts. Months with
    /// no activity at all are skipped so a new user doesn't see a run of $0.00 leading months.
    private func monthlyIncomeLines() -> [String] {
        let calendar = Calendar.current
        let transactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
        guard !transactions.isEmpty else { return [] }

        // Anchor on the later of today and the open month, so a future-month conversation still shows
        // the real income history up to now.
        let anchor = max(Budget.normalize(.now), month)
        let monthsToShow = 12
        var lines: [String] = []
        for offset in stride(from: monthsToShow - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: anchor),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let inMonth = transactions.filter { $0.date >= start && $0.date < end }
            guard !inMonth.isEmpty else { continue }
            let income = inMonth
                .filter { $0.amount > 0 && ($0.category == nil || $0.category?.isIncome == true) }
                .reduce(Decimal(0)) { $0 + $1.amount }
            lines.append("- \(DateFormatting.monthYear(start)) (\(Self.monthKey(start))): \(money(income))")
        }
        return lines
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

    /// A stable "yyyy-MM" formatter (POSIX, gregorian) for reading the tool's `month` argument and
    /// echoing the applied month back to the model — locale-independent so parsing never drifts.
    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    /// Guards against a wildly wrong range spawning a runaway number of budgets — two years of
    /// months is well beyond any reasonable "budget these months" request.
    private static let maxRangeMonths = 24

    /// The months a plan targets, in chronological order: an explicit `startMonth`/`endMonth` range
    /// expands to every month it covers; otherwise a single `month` (or a lone start/end) is used;
    /// and when nothing parses, it falls back to the conversation's month so a malformed argument
    /// never lands a budget on the wrong month or on none at all.
    private func resolveMonths(_ plan: GeminiService.BudgetPlan) -> [Date] {
        if let start = parseMonth(plan.startMonth), let end = parseMonth(plan.endMonth) {
            return monthsInRange(from: start, to: end)
        }
        if let single = parseMonth(plan.month) ?? parseMonth(plan.startMonth) ?? parseMonth(plan.endMonth) {
            return [single]
        }
        return [month]
    }

    /// Every normalized month from `start` to `end` inclusive, ordered and capped at `maxRangeMonths`.
    /// Tolerates a reversed range (end before start) by ordering the bounds first.
    private func monthsInRange(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        let lower = Budget.normalize(min(start, end))
        let upper = Budget.normalize(max(start, end))
        var months: [Date] = []
        var cursor = lower
        while cursor <= upper, months.count < Self.maxRangeMonths {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }

    /// Parses a "yyyy-MM" month string (tolerating a trailing day, e.g. "yyyy-MM-dd") to a
    /// normalized month, or `nil` when it's absent or unparseable.
    private func parseMonth(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        // "yyyy-MM" is what the tool asks for; take the first two components so "yyyy-MM-dd" also works.
        let key = trimmed.split(separator: "-").prefix(2).joined(separator: "-")
        guard let parsed = Self.monthKeyFormatter.date(from: key) else { return nil }
        return Budget.normalize(parsed)
    }

    private static func monthKey(_ date: Date) -> String {
        monthKeyFormatter.string(from: date)
    }

    /// A human label for the applied months: a single month name, or a "first – last (N months)"
    /// range for the multi-month case.
    private static func monthsLabel(_ months: [Date]) -> String {
        guard let first = months.first, let last = months.last else { return "the selected month" }
        if months.count == 1 { return DateFormatting.monthYear(first) }
        return "\(DateFormatting.monthYear(first)) – \(DateFormatting.monthYear(last)) (\(months.count) months)"
    }

    private static func roundedToDollar(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
