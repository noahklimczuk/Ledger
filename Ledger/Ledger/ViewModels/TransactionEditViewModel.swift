import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TransactionEditViewModel {
    struct SplitDraft: Identifiable {
        let id = UUID()
        var category: Category?
        var amountText: String = ""
    }

    /// Whether the entered amount is money out or money in. Users type unsigned amounts; the
    /// sign is applied on save. Without this, "12.50" for a coffee silently recorded as income.
    enum Direction: String, CaseIterable, Identifiable {
        case expense
        case income

        var id: String { rawValue }
        var label: String {
            switch self {
            case .expense: "Expense"
            case .income: "Income"
            }
        }
    }

    var date: Date = .now
    var merchant: String = ""
    var amountText: String = ""
    var direction: Direction = .expense
    var account: Account?
    var category: Category?
    /// The debt this transaction is assigned to, if any. On a *new* transaction, its signed amount
    /// is applied to the debt's balance once on save; on an existing one, changing this only re-links
    /// and never moves the balance.
    var debt: Debt?
    var notes: String = ""
    var splits: [SplitDraft] = []

    private let modelContext: ModelContext
    private let existingTransaction: Transaction?

    var isEditing: Bool { existingTransaction != nil }

    init(modelContext: ModelContext, transaction: Transaction? = nil) {
        self.modelContext = modelContext
        self.existingTransaction = transaction

        if let transaction {
            date = transaction.date
            merchant = transaction.merchant
            direction = transaction.amount > 0 ? .income : .expense
            amountText = Self.string(from: abs(transaction.amount))
            account = transaction.account
            category = transaction.category
            debt = transaction.debt
            notes = transaction.notes ?? ""
            splits = transaction.splits.map { SplitDraft(category: $0.category, amountText: Self.string(from: abs($0.amount))) }
        }
    }

    /// The signed amount that will be saved: the typed magnitude with `direction`'s sign.
    var amount: Decimal? {
        ImportValueParsing.decimal(from: amountText).map { signed(abs($0)) }
    }

    var splitTotal: Decimal {
        splits.reduce(Decimal(0)) { $0 + (ImportValueParsing.decimal(from: $1.amountText).map { signed(abs($0)) } ?? 0) }
    }

    var isSplitValid: Bool {
        guard let amount else { return true }
        return splits.isEmpty || splitTotal == amount
    }

    var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount != nil && account != nil && isSplitValid
    }

    func addSplit() {
        splits.append(SplitDraft())
    }

    func removeSplit(_ draft: SplitDraft) {
        splits.removeAll { $0.id == draft.id }
    }

    @discardableResult
    func save() -> Transaction? {
        guard canSave, let amount, let account else { return nil }

        let categorizer = CategorizationService(modelContext: modelContext)
        let debtAssigner = DebtAssignmentService(modelContext: modelContext)
        let isNew = existingTransaction == nil
        let transaction = existingTransaction ?? Transaction(date: date, merchant: merchant, amount: amount, account: account)
        let previousCategory = transaction.category
        let previousDebt = transaction.debt

        transaction.date = date
        transaction.merchant = merchant
        transaction.amount = amount
        transaction.account = account
        transaction.category = splits.isEmpty ? category : nil
        transaction.debt = debt
        transaction.notes = notes.isEmpty ? nil : notes

        if isNew {
            modelContext.insert(transaction)
            // A new transaction assigned to a debt pays it down (or, for income, adds to it): the
            // signed amount is applied to the balance once, here. Editing an existing transaction —
            // including newly linking or re-linking it — deliberately never touches the balance, so a
            // debt's balance only ever moves for brand-new activity. Floored at zero so an overpayment
            // settles the debt rather than showing a negative amount owed.
            if let debt {
                debt.currentBalance = max(0, debt.currentBalance + amount)
            }
        }

        syncSplits(on: transaction)

        // Auto-categorization: learn from an explicit manual choice, or fill a blank category from
        // a previously-learned rule. Split transactions carry their categories on the splits.
        if transaction.splits.isEmpty {
            if let chosen = category, chosen !== previousCategory {
                categorizer.learn(merchant: merchant, category: chosen)
                // Replay the fresh rule immediately so the merchant's other uncategorized
                // transactions update now, not at the next sync.
                categorizer.categorizeAllUncategorized()
            } else if transaction.category == nil {
                categorizer.applyRule(to: transaction)
            }
        }

        // Debt auto-assignment mirrors categorization: an explicit debt choice teaches the merchant →
        // debt rule and links the merchant's other unassigned transactions (without moving their
        // balances); leaving it blank lets a previously-learned rule fill it in. An explicit choice on
        // a new transaction already moved the balance above, so only the blank-fill path moves it —
        // and only when the transaction is new, matching the "new activity only" balance rule.
        if transaction.splits.isEmpty {
            if let chosen = debt, chosen !== previousDebt {
                debtAssigner.learn(merchant: merchant, debt: chosen)
                debtAssigner.assignAllUnassigned()
            } else if transaction.debt == nil {
                debtAssigner.applyRule(to: transaction, moveBalance: isNew)
            }
        }

        try? modelContext.save()
        return transaction
    }

    private func signed(_ magnitude: Decimal) -> Decimal {
        direction == .expense ? 0 - magnitude : magnitude
    }

    private func syncSplits(on transaction: Transaction) {
        for existing in transaction.splits {
            modelContext.delete(existing)
        }
        transaction.splits = []

        for draft in splits {
            guard let amount = ImportValueParsing.decimal(from: draft.amountText) else { continue }
            let split = SplitAllocation(amount: signed(abs(amount)), category: draft.category)
            split.transaction = transaction
            modelContext.insert(split)
            transaction.splits.append(split)
        }
    }

    private static func string(from decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}
