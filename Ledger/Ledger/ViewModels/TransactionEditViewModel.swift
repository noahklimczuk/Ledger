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

    var date: Date = .now
    var merchant: String = ""
    var amountText: String = ""
    var account: Account?
    var category: Category?
    var notes: String = ""
    var splits: [SplitDraft] = []

    private let modelContext: ModelContext
    private let existingTransaction: Transaction?
    private static let decimalLocale = Locale(identifier: "en_CA")

    var isEditing: Bool { existingTransaction != nil }

    init(modelContext: ModelContext, transaction: Transaction? = nil) {
        self.modelContext = modelContext
        self.existingTransaction = transaction

        if let transaction {
            date = transaction.date
            merchant = transaction.merchant
            amountText = Self.string(from: transaction.amount)
            account = transaction.account
            category = transaction.category
            notes = transaction.notes ?? ""
            splits = transaction.splits.map { SplitDraft(category: $0.category, amountText: Self.string(from: $0.amount)) }
        }
    }

    var amount: Decimal? {
        Decimal(string: amountText, locale: Self.decimalLocale)
    }

    var splitTotal: Decimal {
        splits.reduce(Decimal(0)) { $0 + (Decimal(string: $1.amountText, locale: Self.decimalLocale) ?? 0) }
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
        let transaction = existingTransaction ?? Transaction(date: date, merchant: merchant, amount: amount, account: account)
        let previousCategory = transaction.category

        transaction.date = date
        transaction.merchant = merchant
        transaction.amount = amount
        transaction.account = account
        transaction.category = splits.isEmpty ? category : nil
        transaction.notes = notes.isEmpty ? nil : notes

        if existingTransaction == nil {
            modelContext.insert(transaction)
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

        try? modelContext.save()
        return transaction
    }

    private func syncSplits(on transaction: Transaction) {
        for existing in transaction.splits {
            modelContext.delete(existing)
        }
        transaction.splits = []

        for draft in splits {
            guard let amount = Decimal(string: draft.amountText, locale: Self.decimalLocale) else { continue }
            let split = SplitAllocation(amount: amount, category: draft.category)
            split.transaction = transaction
            modelContext.insert(split)
            transaction.splits.append(split)
        }
    }

    private static func string(from decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}
