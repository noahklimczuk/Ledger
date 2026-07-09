import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var accounts: [Account] = []
    private(set) var recentTransactions: [Transaction] = []
    private(set) var monthSpending: Decimal = 0
    private(set) var monthBudgetTotal: Decimal = 0
    private(set) var safeToSpend: Decimal = 0
    private(set) var isLoading = false

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
        let allTransactions = (try? modelContext.fetch(transactionDescriptor)) ?? []
        recentTransactions = Array(allTransactions.prefix(5))

        let monthTransactions = allTransactions.filter { $0.date >= monthStart && $0.date < monthEnd }
        monthSpending = monthTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
        let monthIncome = monthTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }

        let budgetDescriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.month == monthStart })
        let budgets = (try? modelContext.fetch(budgetDescriptor)) ?? []
        monthBudgetTotal = budgets.reduce(Decimal(0)) { $0 + $1.allocatedAmount }

        safeToSpend = SafeToSpendCalculator.calculate(income: monthIncome, budgetAllocations: monthBudgetTotal)
    }
}
