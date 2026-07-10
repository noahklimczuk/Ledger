import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CategoryEditorViewModel {
    private(set) var categories: [Category] = []
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        categories = (try? modelContext.fetch(descriptor)) ?? []
    }

    var topLevelCategories: [Category] {
        categories.filter { $0.parent == nil }
    }

    func subcategories(of category: Category) -> [Category] {
        let parentId = category.persistentModelID
        return categories.filter { $0.parent?.persistentModelID == parentId }
    }

    func addCategory(name: String, sfSymbolName: String, colorHex: String, isIncome: Bool, parent: Category?) {
        let category = Category(name: name, sfSymbolName: sfSymbolName, colorHex: colorHex, isIncome: isIncome, parent: parent)
        modelContext.insert(category)
        save()
    }

    func updateCategory(_ category: Category, name: String, sfSymbolName: String, colorHex: String, isIncome: Bool) {
        category.name = name
        category.sfSymbolName = sfSymbolName
        category.colorHex = colorHex
        category.isIncome = isIncome
        save()
    }

    /// Deletes the category (and, via cascade, its subcategories). Budgets and learned
    /// categorization rules that pointed at the deleted tree are removed too — left in place
    /// they'd linger as blank "Uncategorized" budget rows and dead rules that still win
    /// longest-keyword matching. Transactions keep their history; their category just nils out.
    func delete(_ category: Category) {
        var deletedIds: Set<PersistentIdentifier> = [category.persistentModelID]
        for sub in category.subcategories { deletedIds.insert(sub.persistentModelID) }

        let budgets = (try? modelContext.fetch(FetchDescriptor<Budget>())) ?? []
        for budget in budgets where budget.category.map({ deletedIds.contains($0.persistentModelID) }) == true {
            modelContext.delete(budget)
        }
        let rules = (try? modelContext.fetch(FetchDescriptor<CategorizationRule>())) ?? []
        for rule in rules where rule.category.map({ deletedIds.contains($0.persistentModelID) }) == true {
            modelContext.delete(rule)
        }

        modelContext.delete(category)
        save()
    }

    private func save() {
        try? modelContext.save()
        load()
    }
}
