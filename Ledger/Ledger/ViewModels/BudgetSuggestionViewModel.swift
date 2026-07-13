import Foundation
import Observation
import SwiftData

/// Drives the AI budget proposal sheet. The flow never touches stored budgets until the user
/// explicitly applies: an on-device baseline proposal is built first (always works, offline),
/// then — when a (free) Google Gemini API key is configured — the summary plus recent transaction
/// lines are sent for AI-tailored amounts and rationales. The proposal always carries a monthly
/// savings set-aside sized to the gap between income and spending. An API failure quietly leaves
/// the on-device proposal in place with a note, never an empty screen.
@MainActor
@Observable
final class BudgetSuggestionViewModel {
    struct ProposalRow: Identifiable {
        var id: PersistentIdentifier { category.persistentModelID }
        let category: Category
        let averageSpend: Decimal
        let recentAverageSpend: Decimal
        var amountText: String
        var rationale: String
        var isIncluded: Bool = true

        var amount: Decimal? { ImportValueParsing.decimal(from: amountText) }
    }

    enum Stage {
        case loading
        case noData
        case review
        case applied
    }

    private(set) var stage: Stage = .loading
    private(set) var rows: [ProposalRow] = []
    /// Plain-English overview from the AI, or an on-device note when the AI path wasn't used.
    private(set) var planSummary: String = ""
    private(set) var averageMonthlyIncome: Decimal = 0
    private(set) var monthsAnalyzed: Int = 0

    /// The monthly savings set-aside, proposed in proportion to the gap between income and
    /// spending. Editable and excludable like any category row; applied to a "Savings" category.
    var savingsAmountText: String = ""
    private(set) var savingsRationale: String = ""
    var savingsIncluded: Bool = true
    var savingsAmount: Decimal? { ImportValueParsing.decimal(from: savingsAmountText) }
    private(set) var isRefining = false
    private(set) var aiStatus: String?
    private(set) var appliedCount = 0

    var apiKeyText: String = ""
    var hasAPIKey: Bool { GeminiService.storedAPIKey != nil }

    let month: Date
    private let modelContext: ModelContext

    init(modelContext: ModelContext, month: Date) {
        self.modelContext = modelContext
        self.month = Budget.normalize(month)
    }

    var totalProposed: Decimal {
        let categories = rows.filter(\.isIncluded).reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        return categories + (savingsIncluded ? (savingsAmount ?? 0) : 0)
    }

    var includedCount: Int { rows.filter(\.isIncluded).count }

    var canApply: Bool {
        guard stage == .review else { return false }
        return rows.contains(where: { $0.isIncluded && $0.amount != nil })
            || (savingsIncluded && (savingsAmount ?? 0) > 0)
    }

    // MARK: - Generation

    /// Builds the on-device proposal, then refines through the API when a key is configured.
    func generate() async {
        stage = .loading
        let service = BudgetSuggestionService(modelContext: modelContext)
        guard let summary = service.summarize(before: month) else {
            stage = .noData
            return
        }

        monthsAnalyzed = summary.months
        averageMonthlyIncome = summary.averageMonthlyIncome
        rows = summary.stats.map { stat in
            ProposalRow(
                category: stat.category,
                averageSpend: stat.average,
                recentAverageSpend: stat.recentAverage,
                amountText: Self.string(from: stat.baselineSuggestion),
                rationale: Self.baselineRationale(for: stat)
            )
        }
        savingsAmountText = Self.string(from: summary.suggestedSavings)
        savingsRationale = Self.baselineSavingsRationale(for: summary)
        savingsIncluded = true
        planSummary = "Based on your average spending over the last \(summary.months) month\(summary.months == 1 ? "" : "s"), with savings sized to what's left of your income. Adjust any amount before applying."
        stage = .review

        await refineWithAI(summary: summary)
    }

    /// Sends the summary (aggregated totals plus recent transaction lines) for tailored amounts.
    /// Failures leave the on-device proposal untouched.
    private func refineWithAI(summary: BudgetSuggestionService.Summary) async {
        guard let apiKey = GeminiService.storedAPIKey else {
            aiStatus = "On-device estimate. Add a free Google Gemini API key for tailored suggestions."
            return
        }

        isRefining = true
        defer { isRefining = false }
        do {
            let suggestion = try await GeminiService().suggestBudget(from: summary, apiKey: apiKey)
            var byName: [String: GeminiService.SuggestedCategory] = [:]
            for category in suggestion.categories {
                byName[category.name.lowercased().trimmingCharacters(in: .whitespaces)] = category
            }
            for index in rows.indices {
                guard let match = byName[rows[index].category.name.lowercased()] , match.amount > 0 else { continue }
                rows[index].amountText = Self.string(from: Self.roundedToDollar(Decimal(match.amount)))
                rows[index].rationale = match.rationale
            }
            if let savings = suggestion.savings, savings.amount >= 0 {
                savingsAmountText = Self.string(from: Self.roundedToDollar(Decimal(savings.amount)))
                savingsRationale = savings.rationale
            }
            planSummary = suggestion.summary
            aiStatus = nil
        } catch {
            aiStatus = "AI refinement unavailable — showing on-device estimates. (\(error.localizedDescription))"
        }
    }

    // MARK: - Mutations

    func setIncluded(_ row: ProposalRow, included: Bool) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].isIncluded = included
    }

    func setAmountText(_ text: String, for row: ProposalRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].amountText = text
    }

    func saveAPIKey() {
        GeminiService.setAPIKey(apiKeyText)
        apiKeyText = ""
    }

    /// Writes the included rows as this month's budgets (updating any that already exist).
    /// Only ever called from the explicit Apply button — nothing is saved before that.
    func apply() {
        let budgetsViewModel = BudgetsViewModel(modelContext: modelContext)
        budgetsViewModel.selectedMonth = month

        var count = 0
        for row in rows where row.isIncluded {
            guard let amount = row.amount, amount > 0 else { continue }
            let existingRollover = budgetsViewModel.rows
                .first { $0.budget.category?.persistentModelID == row.category.persistentModelID }?
                .budget.rolloverEnabled ?? false
            budgetsViewModel.addOrUpdateBudget(category: row.category, allocatedAmount: amount, rolloverEnabled: existingRollover)
            count += 1
        }
        if savingsIncluded, let amount = savingsAmount, amount > 0 {
            let savingsCategory = budgetsViewModel.findOrCreateSavingsCategory()
            let existingRollover = budgetsViewModel.rows
                .first { $0.budget.category?.persistentModelID == savingsCategory.persistentModelID }?
                .budget.rolloverEnabled ?? false
            budgetsViewModel.addOrUpdateBudget(category: savingsCategory, allocatedAmount: amount, rolloverEnabled: existingRollover)
            count += 1
        }
        appliedCount = count
        stage = .applied
    }

    // MARK: - Helpers

    private static func baselineRationale(for stat: BudgetSuggestionService.CategoryStat) -> String {
        if stat.isTrendingUp {
            return "Spending here has been rising — recent months average \(CurrencyFormatter.string(from: stat.recentAverage))."
        }
        if stat.isTrendingDown {
            return "Spending here has been falling — recent months average \(CurrencyFormatter.string(from: stat.recentAverage))."
        }
        return "Steady spending, averaging \(CurrencyFormatter.string(from: stat.average)) a month."
    }

    private static func baselineSavingsRationale(for summary: BudgetSuggestionService.Summary) -> String {
        guard summary.suggestedSavings > 0 else {
            return "Planned spending uses up your average income, so there's no surplus to set aside yet."
        }
        return "The surplus between your average income (\(CurrencyFormatter.string(from: summary.averageMonthlyIncome))/mo) and the proposed spending — savings scale with that gap."
    }

    private static func string(from decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    private static func roundedToDollar(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
