import Foundation
import SwiftData

/// Seeds the built-in budgeting categories and merchant-keyword rules, so a fresh install already
/// has common categories to budget against and can auto-categorize transactions out of the box.
///
/// Seeding is **versioned**: when `DefaultCategoryCatalog.version` grows, the next launch adds the
/// newly introduced categories and any new keywords — without resurrecting categories the user
/// deleted from an earlier catalog version, and without duplicating anything that already exists.
// Not main-actor isolated: pure SwiftData + UserDefaults work, so it can run on a background
// ModelContext (see RefreshDBWorker) to keep first-launch/upgrade seeding off the main thread.
enum DefaultDataSeeder {
    /// Pre-versioning flag (catalog v1). Still read so old installs upgrade as version 1, not 0.
    private static let legacyDidSeedKey = "DefaultDataSeeder.didSeedDefaults.v1"
    private static let seedVersionKey = "DefaultDataSeeder.seedVersion"

    static func seedIfNeeded(modelContext: ModelContext) {
        let seededVersion = storedVersion()
        guard seededVersion < DefaultCategoryCatalog.version else { return }
        seed(modelContext: modelContext, upgradingFrom: seededVersion)
        UserDefaults.standard.set(DefaultCategoryCatalog.version, forKey: seedVersionKey)
    }

    private static func storedVersion() -> Int {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: seedVersionKey)
        if stored > 0 { return stored }
        return defaults.bool(forKey: legacyDidSeedKey) ? 1 : 0
    }

    private static func seed(modelContext: ModelContext, upgradingFrom seededVersion: Int) {
        let existingCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        var byName: [String: Category] = [:]
        for category in existingCategories { byName[category.name.lowercased()] = category }

        let existingRules = (try? modelContext.fetch(FetchDescriptor<CategorizationRule>())) ?? []
        var ruleKeywords = Set(existingRules.map(\.keyword))

        for (index, seed) in DefaultCategoryCatalog.categories.enumerated() {
            var category = byName[seed.name.lowercased()]

            if category == nil {
                // Missing category: create it only if this catalog version introduces it. A
                // category from an already-seeded version that's absent now was deleted by the
                // user — honor that instead of bringing it back.
                guard seed.introducedInVersion > seededVersion else { continue }
                let created = Category(
                    name: seed.name,
                    sfSymbolName: seed.symbol,
                    colorHex: seed.colorHex,
                    isIncome: seed.isIncome,
                    isTransfer: seed.isTransfer,
                    sortOrder: index
                )
                modelContext.insert(created)
                byName[seed.name.lowercased()] = created
                category = created
            }

            guard let category else { continue }

            // Non-destructively adopt the transfer flag onto an existing built-in category (e.g. an
            // older install's "Transfers"), so transfers stop counting toward income/spending.
            if seed.isTransfer && !category.isTransfer {
                category.isTransfer = true
            }

            for rawKeyword in seed.keywords {
                let keyword = CategorizationService.keyword(for: rawKeyword)
                guard !keyword.isEmpty, !ruleKeywords.contains(keyword) else { continue }
                // matchCount 0 so a user's own learned rule (which starts at 1) outranks a
                // built-in default when their keywords tie on length.
                modelContext.insert(CategorizationRule(keyword: keyword, category: category, matchCount: 0))
                ruleKeywords.insert(keyword)
            }
        }

        try? modelContext.save()

        // New rules can unlock categories for transactions that predate them.
        CategorizationService(modelContext: modelContext).categorizeAllUncategorized()
    }
}
