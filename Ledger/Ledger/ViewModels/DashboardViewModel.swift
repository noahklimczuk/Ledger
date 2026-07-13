import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DashboardViewModel {
    struct CategorySlice: Identifiable {
        var id: String { name }
        let name: String
        let colorHex: String
        let amount: Decimal
        /// The category behind this slice, so a tapped doughnut slice can drill into its
        /// transactions. Nil for the synthetic "Uncategorized" bucket.
        let category: Category?
    }

    private(set) var accounts: [Account] = []
    private(set) var recentTransactions: [Transaction] = []
    private(set) var monthSpending: Decimal = 0
    private(set) var monthIncome: Decimal = 0
    private(set) var monthBudgetTotal: Decimal = 0
    private(set) var safeToSpend: Decimal = 0
    /// Upcoming bills + detected recurring charges reserved out of Safe to Spend this month.
    private(set) var reservedForBills: Decimal = 0
    private(set) var topCategories: [CategorySlice] = []

    /// Income minus spending for the current month.
    var monthNet: Decimal { monthIncome - monthSpending }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var totalBalance: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.currentBalance }
    }

    func load() {
        let accountDescriptor = FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        accounts = (try? modelContext.fetch(accountDescriptor)) ?? []

        let calendar = Calendar.current
        let monthStart = Budget.normalize(.now)
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1), to: monthStart) ?? monthStart

        let transactionDescriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let allTransactions = ((try? modelContext.fetch(transactionDescriptor)) ?? [])
            .filter(\.countsTowardTotals)
        recentTransactions = Array(allTransactions.prefix(5))

        let monthTransactions = allTransactions.filter { $0.date >= monthStart && $0.date < monthEnd }
        // Transfers between accounts aren't income or spending, so keep them out of these totals.
        let nonTransfer = monthTransactions.filter { !$0.isTransfer }
        monthSpending = nonTransfer.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
        monthIncome = nonTransfer.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        topCategories = computeTopCategories(nonTransfer)

        let budgetDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart })
        let budgets = (try? modelContext.fetch(budgetDescriptor)) ?? []
        monthBudgetTotal = budgets.reduce(Decimal(0)) { $0 + $1.allocatedAmount }

        // Reserve money that's already spoken for — upcoming bills and detected recurring
        // charges — so Safe to Spend never shows rent money as spendable.
        let bills = (try? modelContext.fetch(FetchDescriptor<BillReminder>())) ?? []
        let recurring = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? []
        reservedForBills = SafeToSpendCalculator.upcomingCommitments(bills: bills, recurring: recurring)

        safeToSpend = SafeToSpendCalculator.calculate(
            income: monthIncome,
            budgetAllocations: monthBudgetTotal,
            committedBills: reservedForBills
        )
    }

    /// The month's biggest spending categories (split-aware), for the dashboard breakdown chart.
    private func computeTopCategories(_ transactions: [Transaction]) -> [CategorySlice] {
        var totals: [String: (colorHex: String, amount: Decimal, category: Category?)] = [:]

        func add(category: Category?, amount: Decimal) {
            guard amount < 0, category?.isTransfer != true else { return }
            let name = category?.name ?? "Uncategorized"
            let colorHex = category?.colorHex ?? "#8E8E93"
            let existing = totals[name] ?? (colorHex, 0, category)
            // Keep the first real category seen for this name so the slice can drill in.
            totals[name] = (existing.colorHex, existing.amount + (-amount), existing.category ?? category)
        }

        for transaction in transactions {
            if transaction.isSplit {
                for split in transaction.splits {
                    add(category: split.category, amount: split.amount)
                }
            } else {
                add(category: transaction.category, amount: transaction.amount)
            }
        }

        return totals
            .map { CategorySlice(name: $0.key, colorHex: $0.value.colorHex, amount: $0.value.amount, category: $0.value.category) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }
}
