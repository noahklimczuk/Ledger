import Foundation
import SwiftData

@Model
final class SplitAllocation {
    var amount: Decimal
    var notes: String?

    var transaction: Transaction?
    var category: Category?

    init(amount: Decimal, category: Category?, notes: String? = nil) {
        self.amount = amount
        self.category = category
        self.notes = notes
    }
}
