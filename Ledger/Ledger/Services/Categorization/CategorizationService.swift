import Foundation
import SwiftData

/// Learns merchant → category rules from the user's manual categorizations and replays them onto
/// future and imported transactions. Rules are stored as `CategorizationRule` (schema present since
/// phase 1). Keywords are normalized the same way `RecurringDetectionService` normalizes merchants,
/// so store numbers, punctuation and casing don't defeat matching (e.g. "SQ *BLUE BOTTLE #123" and
/// "SQ *BLUE BOTTLE #987" both reduce to "blue bottle").
@MainActor
final class CategorizationService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records (or updates) the rule implied by the user assigning `category` to `merchant`.
    func learn(merchant: String, category: Category) {
        let keyword = Self.keyword(for: merchant)
        guard !keyword.isEmpty else { return }

        let descriptor = FetchDescriptor<CategorizationRule>(predicate: #Predicate { $0.keyword == keyword })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.category = category
        } else {
            modelContext.insert(CategorizationRule(keyword: keyword, category: category))
        }
    }

    /// The category a stored rule would assign to `merchant`, or nil. Read-only — no match counting.
    func suggestedCategory(forMerchant merchant: String) -> Category? {
        bestRule(forMerchant: merchant)?.category
    }

    /// Fills in `transaction.category` from the best matching rule when it's uncategorized and not
    /// split. Returns true if a category was applied, and bumps the matched rule's `matchCount`.
    @discardableResult
    func applyRule(to transaction: Transaction) -> Bool {
        guard transaction.category == nil, transaction.splits.isEmpty else { return false }
        guard let rule = bestRule(forMerchant: transaction.merchant), let category = rule.category else { return false }
        transaction.category = category
        rule.matchCount += 1
        return true
    }

    // MARK: - Matching

    /// The most specific rule whose keyword is contained in the (normalized) merchant. Longest
    /// keyword wins; ties break toward the rule that has matched more often.
    private func bestRule(forMerchant merchant: String) -> CategorizationRule? {
        let normalized = Self.keyword(for: merchant)
        guard !normalized.isEmpty else { return nil }

        let rules = (try? modelContext.fetch(FetchDescriptor<CategorizationRule>())) ?? []
        return rules
            .filter { !$0.keyword.isEmpty && normalized.contains($0.keyword) }
            .max { ($0.keyword.count, $0.matchCount) < ($1.keyword.count, $1.matchCount) }
    }

    static func keyword(for merchant: String) -> String {
        RecurringDetectionService.normalizeMerchant(merchant)
    }
}
