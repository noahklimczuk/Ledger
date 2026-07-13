import Foundation
import SwiftData

@Model
final class Category {
    var name: String
    var sfSymbolName: String
    var colorHex: String
    var isIncome: Bool
    /// A transfer category (e.g. moving money between your own accounts). Its transactions are
    /// excluded from income and spending totals — they aren't earnings or purchases — while still
    /// affecting account balances and net worth (the two sides of a transfer cancel out). A
    /// category is at most one of income or transfer; both false means an ordinary expense.
    var isTransfer: Bool = false
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
        isTransfer: Bool = false,
        parent: Category? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.sfSymbolName = sfSymbolName
        self.colorHex = colorHex
        self.isIncome = isIncome
        self.isTransfer = isTransfer
        self.parent = parent
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    var isSubcategory: Bool { parent != nil }
}
