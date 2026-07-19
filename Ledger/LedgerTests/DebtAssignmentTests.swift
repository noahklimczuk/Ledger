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
struct DebtAssignmentTests {
    /// Teaching a rule and back-filling existing transactions links them but must not move the
    /// balance — historical rows shouldn't retroactively pay a debt down.
    @Test func learnsAndBackfillsWithoutMovingBalance() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let debt = Debt(name: "Visa", kind: .creditCard, currentBalance: 1000)
        context.insert(account)
        context.insert(debt)
        let first = Transaction(date: day(2026, 1, 15), merchant: "VISA PAYMENT #4021", amount: -200, account: account)
        let second = Transaction(date: day(2026, 2, 15), merchant: "VISA PAYMENT #7788", amount: -200, account: account)
        context.insert(first)
        context.insert(second)
        try context.save()

        let service = DebtAssignmentService(modelContext: context)
        // The user files the first payment under the debt (teaching the rule). The balance is the
        // user's own figure, so learning + back-fill leave it alone.
        service.learn(merchant: first.merchant, debt: debt)
        first.debt = debt
        let linked = service.assignAllUnassigned()

        #expect(linked == 1)
        #expect(second.debt === debt)
        #expect(debt.currentBalance == 1000)
    }

    /// A freshly imported payment matching a rule auto-assigns and pays the debt down once.
    @Test func appliesRuleToImportedTransactionAndMovesBalanceOnce() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let debt = Debt(name: "Visa", kind: .creditCard, currentBalance: 1000)
        context.insert(account)
        context.insert(debt)
        try context.save()

        let service = DebtAssignmentService(modelContext: context)
        service.learn(merchant: "VISA PAYMENT #1", debt: debt)

        let imported = Transaction(date: day(2026, 3, 15), merchant: "VISA PAYMENT #999", amount: -250, account: account)
        context.insert(imported)
        let applied = service.applyRule(to: imported, moveBalance: true)

        #expect(applied)
        #expect(imported.debt === debt)
        #expect(debt.currentBalance == 750)

        // Re-running is a no-op — an already-assigned transaction never double-charges the balance.
        #expect(service.applyRule(to: imported, moveBalance: true) == false)
        #expect(debt.currentBalance == 750)
    }

    /// No learned rule → nothing is assigned and no balance moves.
    @Test func doesNotAssignWhenNoRuleMatches() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let debt = Debt(name: "Visa", kind: .creditCard, currentBalance: 1000)
        context.insert(account)
        context.insert(debt)

        let transaction = Transaction(date: day(2026, 3, 15), merchant: "GROCERY STORE", amount: -80, account: account)
        context.insert(transaction)

        let service = DebtAssignmentService(modelContext: context)
        #expect(service.applyRule(to: transaction, moveBalance: true) == false)
        #expect(transaction.debt == nil)
        #expect(debt.currentBalance == 1000)
    }

    /// The most specific rule wins: "visa payment" outranks a bare "visa".
    @Test func longerKeywordWins() throws {
        let context = try makeContext()
        let account = Account(name: "Chequing", type: .chequing)
        let card = Debt(name: "Visa card", kind: .creditCard, currentBalance: 500)
        let loan = Debt(name: "Visa loan", kind: .personalLoan, currentBalance: 500)
        context.insert(account)
        context.insert(card)
        context.insert(loan)

        let service = DebtAssignmentService(modelContext: context)
        service.learn(merchant: "visa", debt: loan)
        service.learn(merchant: "visa payment", debt: card)

        let transaction = Transaction(date: day(2026, 3, 15), merchant: "VISA PAYMENT #12", amount: -100, account: account)
        context.insert(transaction)
        service.applyRule(to: transaction, moveBalance: false)

        #expect(transaction.debt === card)
    }
}
