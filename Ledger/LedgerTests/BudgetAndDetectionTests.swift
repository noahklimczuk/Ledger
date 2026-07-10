import Foundation
import SwiftData
import Testing
@testable import Ledger

/// Fresh in-memory store per test, so SwiftData-backed logic runs without touching disk.
@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema(LedgerSchema.models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return container.mainContext
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
}

@MainActor
struct RecurringDetectionTests {
    @Test func detectsMonthlySubscription() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        context.insert(account)
        for month in 1...4 {
            context.insert(Transaction(date: day(2026, month, 15), merchant: "NETFLIX.COM", amount: -20, account: account))
        }

        let detected = RecurringDetectionService(modelContext: context).detect(in: try context.fetch(FetchDescriptor<Transaction>()))
        let netflix = detected.first { $0.merchantKey == "netflix com" }
        #expect(netflix != nil)
        #expect(netflix?.cadence == .monthly)
        #expect(netflix?.averageAmount == -20)
        #expect(netflix?.occurrenceCount == 4)
    }

    @Test func ignoresIrregularMerchants() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        context.insert(account)
        // Frequent but irregular: gaps of 3, 2, 9, 1 days resemble no cadence.
        for dayOfMonth in [1, 4, 6, 15, 16] {
            context.insert(Transaction(date: day(2026, 3, dayOfMonth), merchant: "GROCER", amount: -60, account: account))
        }

        let detected = RecurringDetectionService(modelContext: context).detect(in: try context.fetch(FetchDescriptor<Transaction>()))
        #expect(detected.isEmpty)
    }
}

@MainActor
struct BudgetRolloverTests {
    @Test func rolloverCompoundsAcrossConsecutiveMonths() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let groceries = Category(name: "Groceries")
        context.insert(account)
        context.insert(groceries)

        // Jan: 500 budgeted, 400 spent (+100). Feb: 500 budgeted, 550 spent (carry absorbs 50).
        // Mar: 500 budgeted, nothing spent (+500). Carry into Apr = 100 - 50 + 500 = 550.
        for (month, spent) in [(1, 400), (2, 550), (3, 0)] {
            context.insert(Budget(month: day(2026, month, 1), category: groceries, allocatedAmount: 500, rolloverEnabled: true))
            if spent > 0 {
                context.insert(Transaction(date: day(2026, month, 10), merchant: "Store", amount: Decimal(-spent), account: account, category: groceries))
            }
        }
        context.insert(Budget(month: day(2026, 4, 1), category: groceries, allocatedAmount: 500, rolloverEnabled: true))
        try context.save()

        let viewModel = BudgetsViewModel(modelContext: context)
        viewModel.selectedMonth = Budget.normalize(day(2026, 4, 1))

        let row = viewModel.rows.first { $0.budget.category?.persistentModelID == groceries.persistentModelID }
        #expect(row?.rolloverFromPreviousMonth == 550)
        #expect(row?.allocatedIncludingRollover == 1050)
    }

    @Test func monthWithoutRolloverBudgetBreaksTheChain() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let travel = Category(name: "Travel")
        context.insert(account)
        context.insert(travel)

        // Jan has a rollover budget with leftover, but Feb and Mar have no budget at all —
        // the chain breaks, so nothing reaches April.
        context.insert(Budget(month: day(2026, 1, 1), category: travel, allocatedAmount: 300, rolloverEnabled: true))
        context.insert(Budget(month: day(2026, 4, 1), category: travel, allocatedAmount: 300, rolloverEnabled: true))
        try context.save()

        let viewModel = BudgetsViewModel(modelContext: context)
        viewModel.selectedMonth = Budget.normalize(day(2026, 4, 1))

        let row = viewModel.rows.first { $0.budget.category?.persistentModelID == travel.persistentModelID }
        #expect(row?.rolloverFromPreviousMonth == 0)
    }

    @Test func archivedAccountSpendingIsExcluded() throws {
        let context = try makeContext()
        let active = Account(name: "Chequing", type: .chequing)
        let archived = Account(name: "Old", type: .chequing, isArchived: true)
        let dining = Category(name: "Dining")
        context.insert(active)
        context.insert(archived)
        context.insert(dining)
        context.insert(Budget(month: day(2026, 4, 1), category: dining, allocatedAmount: 200))
        context.insert(Transaction(date: day(2026, 4, 5), merchant: "Cafe", amount: -50, account: active, category: dining))
        context.insert(Transaction(date: day(2026, 4, 6), merchant: "Cafe", amount: -999, account: archived, category: dining))
        try context.save()

        let viewModel = BudgetsViewModel(modelContext: context)
        viewModel.selectedMonth = Budget.normalize(day(2026, 4, 1))

        let row = viewModel.rows.first { $0.budget.category?.persistentModelID == dining.persistentModelID }
        #expect(row?.spent == 50)
    }
}

@MainActor
struct BudgetSuggestionServiceTests {
    @Test func summarizesAveragesAndIncome() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let groceries = Category(name: "Groceries")
        let salary = Category(name: "Salary", isIncome: true)
        context.insert(account)
        context.insert(groceries)
        context.insert(salary)

        for month in 1...3 {
            context.insert(Transaction(date: day(2026, month, 10), merchant: "Store", amount: -300, account: account, category: groceries))
            context.insert(Transaction(date: day(2026, month, 1), merchant: "Employer", amount: 1000, account: account, category: salary))
        }
        try context.save()

        let summary = BudgetSuggestionService(modelContext: context).summarize(before: day(2026, 4, 1), months: 3)
        #expect(summary != nil)
        #expect(summary?.months == 3)
        #expect(summary?.averageMonthlyIncome == 1000)

        let stat = summary?.stats.first { $0.category.persistentModelID == groceries.persistentModelID }
        #expect(stat?.average == 300)
        #expect(stat?.monthlyTotals == [300, 300, 300])
        #expect(stat?.baselineSuggestion == 300)
        // Income categories never become budget suggestions.
        #expect(summary?.stats.contains { $0.category.isIncome } == false)
    }

    @Test func returnsNilWithoutHistory() throws {
        let context = try makeContext()
        #expect(BudgetSuggestionService(modelContext: context).summarize(before: day(2026, 4, 1)) == nil)
    }
}
