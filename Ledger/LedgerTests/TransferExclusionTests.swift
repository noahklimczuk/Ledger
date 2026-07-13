import Foundation
import SwiftData
import Testing
@testable import Ledger

@MainActor
struct TransferExclusionTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(LedgerSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration]).mainContext
    }

    @Test func transfersDoNotCountAsIncomeOrSpending() throws {
        let context = try makeContext()
        let account = Account(name: "Cash", type: .chequing)
        context.insert(account)

        let salary = Category(name: "Salary", isIncome: true)
        let food = Category(name: "Food")
        let transfers = Category(name: "Transfers", isTransfer: true)
        for category in [salary, food, transfers] { context.insert(category) }

        context.insert(Transaction(date: .now, merchant: "Payroll", amount: 1000, account: account, category: salary))
        context.insert(Transaction(date: .now, merchant: "Grocer", amount: -80, account: account, category: food))
        // A transfer in and a transfer out — neither should move income or spending.
        context.insert(Transaction(date: .now, merchant: "From Savings", amount: 500, account: account, category: transfers))
        context.insert(Transaction(date: .now, merchant: "To Savings", amount: -300, account: account, category: transfers))
        try context.save()

        let dashboard = DashboardViewModel(modelContext: context)
        dashboard.load()
        #expect(dashboard.monthIncome == 1000)
        #expect(dashboard.monthSpending == 80)
        // The transfer category must not appear as a spending slice.
        #expect(!dashboard.topCategories.contains { $0.name == "Transfers" })

        let reports = ReportsViewModel(modelContext: context)
        reports.range = .thisMonth
        reports.load()
        #expect(reports.totalIncome == 1000)
        #expect(reports.totalExpense == 80)
        #expect(!reports.categorySpending.contains { $0.name == "Transfers" })

        // But the transfer still affects the account balance (money actually moved).
        #expect(account.currentBalance == 1000 - 80 + 500 - 300)
    }
}
