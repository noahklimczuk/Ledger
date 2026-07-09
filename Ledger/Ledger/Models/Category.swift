import Foundation
import SwiftData

@Model
final class Category {
    var name: String
    var sfSymbolName: String
    var colorHex: String
    var isIncome: Bool
    var sortOrder: Int
    var createdAt: Date

    var parent: Category?

    @Relationship(deleteRule: .cascade, inverse: \Category.parent)
    var subcategories: [Category] = []

    init(
        name: String,
        sfSymbolName: String = "circle.fill",
        colorHex: String = "#8E8E93",
        isIncome: Bool = false,
        parent: Category? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.sfSymbolName = sfSymbolName
        self.colorHex = colorHex
        self.isIncome = isIncome
        self.parent = parent
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    var isSubcategory: Bool { parent != nil }
}
