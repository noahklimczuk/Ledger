import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DebtsViewModel {
    private(set) var debts: [Debt] = []
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let descriptor = FetchDescriptor<Debt>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.currentBalance, order: .reverse)]
        )
        debts = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Total amount still owed across all tracked debts.
    var totalOwed: Decimal {
        debts.reduce(Decimal(0)) { $0 + $1.currentBalance }
    }

    /// Total of the monthly payments the user has committed to across all debts.
    var totalMonthlyPayment: Decimal {
        debts.reduce(Decimal(0)) { $0 + $1.minimumPayment }
    }

    func addDebt(name: String, kind: DebtKind, currentBalance: Decimal, annualInterestRate: Double, minimumPayment: Decimal, notes: String?) {
        let debt = Debt(
            name: name,
            kind: kind,
            currentBalance: currentBalance,
            annualInterestRate: annualInterestRate,
            minimumPayment: minimumPayment,
            notes: notes
        )
        modelContext.insert(debt)
        save()
    }

    func updateDebt(_ debt: Debt, name: String, kind: DebtKind, currentBalance: Decimal, annualInterestRate: Double, minimumPayment: Decimal, notes: String?) {
        debt.name = name
        debt.kind = kind
        debt.currentBalance = currentBalance
        debt.annualInterestRate = annualInterestRate
        debt.minimumPayment = minimumPayment
        debt.notes = notes
        save()
    }

    func delete(_ debt: Debt) {
        modelContext.delete(debt)
        save()
    }

    private func save() {
        try? modelContext.save()
        load()
    }
}
