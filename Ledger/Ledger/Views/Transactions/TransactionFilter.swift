import Foundation

/// Filter criteria for the Transactions tab. The list itself is a live SwiftData `@Query`;
/// this struct only carries what the filter sheet collects.
struct TransactionFilter {
    /// Money direction. Expenses are negative amounts, income is positive.
    enum Kind: String, CaseIterable, Identifiable {
        case all
        case expenses
        case income

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .expenses: "Expenses"
            case .income: "Income"
            }
        }
    }

    /// Whether a transaction has been reviewed yet.
    enum ReviewState: String, CaseIterable, Identifiable {
        case all
        case needsReview
        case reviewed

        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .needsReview: "Needs Review"
            case .reviewed: "Reviewed"
            }
        }
    }

    var kind: Kind = .all
    var reviewState: ReviewState = .all
    var account: Account?
    var category: Category?
    var startDate: Date?
    var endDate: Date?
    var minAmount: Decimal?
    var maxAmount: Decimal?

    var isActive: Bool {
        kind != .all || reviewState != .all || account != nil || category != nil
            || startDate != nil || endDate != nil || minAmount != nil || maxAmount != nil
    }
}
