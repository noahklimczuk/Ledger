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

    func delete(_ category: Category) {
        modelContext.delete(category)
        save()
    }

    private func save() {
        try? modelContext.save()
        load()
    }
}
