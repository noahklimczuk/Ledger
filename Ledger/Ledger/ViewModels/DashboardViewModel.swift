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
    private(set) var isLoading = false

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
        isLoading = true
        defer { isLoading = false }

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
        monthSpending = monthTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
        monthIncome = monthTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        topCategories = computeTopCategories(monthTransactions)

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
        var totals: [String: (colorHex: String, amount: Decimal)] = [:]

        func add(name: String, colorHex: String, amount: Decimal) {
            guard amount < 0 else { return }
            let existing = totals[name] ?? (colorHex, 0)
            totals[name] = (existing.colorHex, existing.amount + (-amount))
        }

        for transaction in transactions {
            if transaction.isSplit {
                for split in transaction.splits {
                    add(name: split.category?.name ?? "Uncategorized", colorHex: split.category?.colorHex ?? "#8E8E93", amount: split.amount)
                }
            } else {
                add(name: transaction.category?.name ?? "Uncategorized", colorHex: transaction.category?.colorHex ?? "#8E8E93", amount: transaction.amount)
            }
        }

        return totals
            .map { CategorySlice(name: $0.key, colorHex: $0.value.colorHex, amount: $0.value.amount) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }
}
