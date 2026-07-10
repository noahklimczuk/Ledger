import Foundation
import SwiftData

/// Learns merchant → category rules from the user's manual categorizations and replays them onto
/// future and imported transactions. Rules are stored as `CategorizationRule`. Keywords are
/// normalized the same way `RecurringDetectionService` normalizes merchants, so store numbers,
/// punctuation and casing don't defeat matching (e.g. "SQ *BLUE BOTTLE #123" and
/// "SQ *BLUE BOTTLE #987" both reduce to "blue bottle").
///
/// Matching is token-aware, not raw substring: a keyword must start at a word boundary, and short
/// keywords (under 5 characters) must match a whole token. That's what keeps "esso" from firing
/// inside "espresso", "gym" inside "gymboree", or "rent" inside "rental car", while still letting
/// "mcdonald" match "mcdonalds" and "chiropract" match "chiropractor".
@MainActor
final class CategorizationService {
    /// Keywords at least this long may match as a token *prefix* ("mcdonald" → "mcdonalds");
    /// shorter ones must match a whole token exactly.
    private static let prefixMatchMinimumLength = 5

    private let modelContext: ModelContext
    /// Rules are fetched once per service instance and reused across every match — a sync that
    /// imports hundreds of transactions does one fetch, not one per transaction. Invalidated by
    /// `learn`, the only path that changes the rule set mid-instance.
    private var cachedRules: [CategorizationRule]?

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
        cachedRules = nil
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

    /// Applies the learned/built-in rules to every currently uncategorized, non-split transaction.
    /// Called on launch, after a sync/import, and right after the user teaches a new rule, so a
    /// manual categorization propagates to the merchant's other transactions immediately.
    /// Returns the number newly categorized.
    @discardableResult
    func categorizeAllUncategorized() -> Int {
        let descriptor = FetchDescriptor<Transaction>()
        let transactions = (try? modelContext.fetch(descriptor)) ?? []
        var count = 0
        for transaction in transactions where transaction.category == nil && transaction.splits.isEmpty {
            if applyRule(to: transaction) { count += 1 }
        }
        if count > 0 { try? modelContext.save() }
        return count
    }

    // MARK: - Matching

    /// The most specific rule matching the (normalized) merchant. Longest keyword wins; ties break
    /// toward the rule that has matched more often — so "uber eats" outranks "uber", and a user's
    /// learned rule (matchCount ≥ 1) outranks a built-in default (matchCount 0) of equal length.
    private func bestRule(forMerchant merchant: String) -> CategorizationRule? {
        let normalized = Self.keyword(for: merchant)
        guard !normalized.isEmpty else { return nil }

        return rules()
            .filter { Self.matches(keyword: $0.keyword, normalizedMerchant: normalized) }
            .max { ($0.keyword.count, $0.matchCount) < ($1.keyword.count, $1.matchCount) }
    }

    /// Token-boundary matching. The keyword must begin at a token boundary; keywords shorter than
    /// `prefixMatchMinimumLength` must also *end* on one.
    static func matches(keyword: String, normalizedMerchant: String) -> Bool {
        guard !keyword.isEmpty else { return false }
        let padded = " " + normalizedMerchant + " "
        if padded.contains(" " + keyword + " ") { return true }
        guard keyword.count >= prefixMatchMinimumLength else { return false }
        return padded.contains(" " + keyword)
    }

    private func rules() -> [CategorizationRule] {
        if let cachedRules { return cachedRules }
        let fetched = (try? modelContext.fetch(FetchDescriptor<CategorizationRule>())) ?? []
        cachedRules = fetched
        return fetched
    }

    static func keyword(for merchant: String) -> String {
        RecurringDetectionService.normalizeMerchant(merchant)
    }
}
