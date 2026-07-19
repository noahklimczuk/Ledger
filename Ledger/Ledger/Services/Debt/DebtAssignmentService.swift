import Foundation
import SwiftData

/// Learns merchant → debt rules from the user's manual debt assignments and replays them onto future
/// and imported transactions — the debt-tracker sibling of `CategorizationService`. It reuses that
/// service's normalization and token-boundary matcher, so store numbers, punctuation, and casing
/// don't defeat matching ("VISA PAYMENT #4021" and "VISA PAYMENT #7788" both reduce to "visa
/// payment").
///
/// Balance safety: assigning a transaction to a debt can move the debt's balance, so — matching the
/// manual editor's rule that a balance "only ever moves for brand-new activity" — the balance is
/// moved only when `moveBalance` is true (freshly imported or newly created transactions), never when
/// back-filling links onto transactions that already existed. And `applyRule` only ever touches a
/// transaction whose `debt` is still nil, so a given transaction's amount is applied at most once.
///
/// Explicitly `nonisolated` (like the categorizer) so `TransactionSyncActor` can run it on its
/// background context; `@MainActor` callers use it inline.
nonisolated final class DebtAssignmentService {
    private let modelContext: ModelContext
    /// Rules are fetched once per instance and reused across every match; invalidated by `learn`.
    private var cachedRules: [DebtRule]?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records (or updates) the rule implied by the user assigning `debt` to `merchant`.
    func learn(merchant: String, debt: Debt) {
        let keyword = Self.keyword(for: merchant)
        guard !keyword.isEmpty else { return }

        let descriptor = FetchDescriptor<DebtRule>(predicate: #Predicate { $0.keyword == keyword })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.debt = debt
        } else {
            modelContext.insert(DebtRule(keyword: keyword, debt: debt))
        }
        cachedRules = nil
    }

    /// The debt a stored rule would assign to `merchant`, or nil. Read-only — no match counting.
    func suggestedDebt(forMerchant merchant: String) -> Debt? {
        bestRule(forMerchant: merchant)?.debt
    }

    /// Fills in `transaction.debt` from the best matching rule when it's unassigned and not split.
    /// When `moveBalance` is true, the transaction's signed amount is applied to the debt's balance
    /// once (floored at zero), the same way the manual editor pays a debt down on a new transaction.
    /// Returns true if a debt was applied, and bumps the matched rule's `matchCount`.
    @discardableResult
    func applyRule(to transaction: Transaction, moveBalance: Bool) -> Bool {
        guard transaction.debt == nil, transaction.splits.isEmpty else { return false }
        guard let rule = bestRule(forMerchant: transaction.merchant), let debt = rule.debt else { return false }
        transaction.debt = debt
        rule.matchCount += 1
        if moveBalance {
            debt.currentBalance = max(0, debt.currentBalance + transaction.amount)
        }
        return true
    }

    /// Applies the learned rules to every currently unassigned, non-split transaction. Back-fill by
    /// default leaves balances untouched (`moveBalance: false`) — it links historical transactions to
    /// their debt without retroactively moving money. Returns the number newly assigned.
    @discardableResult
    func assignAllUnassigned(moveBalance: Bool = false) -> Int {
        let transactions = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        var count = 0
        for transaction in transactions where transaction.debt == nil && transaction.splits.isEmpty {
            if applyRule(to: transaction, moveBalance: moveBalance) { count += 1 }
        }
        if count > 0 { try? modelContext.save() }
        return count
    }

    // MARK: - Matching

    /// The most specific rule matching the merchant. Longest keyword wins; ties break toward the rule
    /// that has matched more often. Reuses the categorizer's token-boundary matcher so "visa payment"
    /// outranks "visa" and short keywords still match on whole tokens only.
    private func bestRule(forMerchant merchant: String) -> DebtRule? {
        let normalized = Self.keyword(for: merchant)
        guard !normalized.isEmpty else { return nil }

        return rules()
            .filter { CategorizationService.matches(keyword: $0.keyword, normalizedMerchant: normalized) }
            .max { ($0.keyword.count, $0.matchCount) < ($1.keyword.count, $1.matchCount) }
    }

    private func rules() -> [DebtRule] {
        if let cachedRules { return cachedRules }
        // A rule whose debt was deleted can never apply; drop it so it can't shadow a live one.
        let fetched = ((try? modelContext.fetch(FetchDescriptor<DebtRule>())) ?? [])
            .filter { $0.debt != nil }
        cachedRules = fetched
        return fetched
    }

    static func keyword(for merchant: String) -> String {
        RecurringDetectionService.normalizeMerchant(merchant)
    }
}
