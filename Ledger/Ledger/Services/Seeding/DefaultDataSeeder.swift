import Foundation
import SwiftData

/// Seeds the built-in budgeting categories and merchant-keyword rules on first launch, so a fresh
/// install already has common categories to budget against and can auto-categorize transactions
/// out of the box. Runs once (guarded by a persisted flag) and never re-adds categories the user
/// later deletes.
@MainActor
enum DefaultDataSeeder {
    private static let didSeedKey = "DefaultDataSeeder.didSeedDefaults.v1"

    /// Inserts the default categories + categorization rules the first time it runs. Idempotent:
    /// subsequent calls are no-ops once the flag is set, and even a forced re-run skips categories
    /// that already exist by name.
    static func seedIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didSeedKey) else { return }
        seed(modelContext: modelContext)
        UserDefaults.standard.set(true, forKey: didSeedKey)
    }

    private static func seed(modelContext: ModelContext) {
        let existing = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        var byName: [String: Category] = [:]
        for category in existing { byName[category.name.lowercased()] = category }

        for (index, seed) in DefaultCategoryCatalog.categories.enumerated() {
            let category: Category
            if let match = byName[seed.name.lowercased()] {
                category = match
            } else {
                let created = Category(
                    name: seed.name,
                    sfSymbolName: seed.symbol,
                    colorHex: seed.colorHex,
                    isIncome: seed.isIncome,
                    sortOrder: index
                )
                modelContext.insert(created)
                byName[seed.name.lowercased()] = created
                category = created
            }

            for rawKeyword in seed.keywords {
                let keyword = CategorizationService.keyword(for: rawKeyword)
                guard !keyword.isEmpty else { continue }
                let descriptor = FetchDescriptor<CategorizationRule>(predicate: #Predicate { $0.keyword == keyword })
                if (try? modelContext.fetch(descriptor).first) == nil {
                    // matchCount 0 so a user's own learned rule (which starts at 1) outranks a
                    // built-in default when their keywords tie on length.
                    modelContext.insert(CategorizationRule(keyword: keyword, category: category, matchCount: 0))
                }
            }
        }

        try? modelContext.save()
    }
}
