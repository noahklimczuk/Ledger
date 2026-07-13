import Foundation

/// Filter criteria for the Transactions tab. The list itself is a live SwiftData `@Query`;
/// this struct only carries what the filter sheet collects.
struct TransactionFilter {
    var account: Account?
    var category: Category?
    var startDate: Date?
    var endDate: Date?
    var minAmount: Decimal?
    var maxAmount: Decimal?

    var isActive: Bool {
        account != nil || category != nil || startDate != nil || endDate != nil || minAmount != nil || maxAmount != nil
    }
}
