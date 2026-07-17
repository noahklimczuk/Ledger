import Foundation
import SwiftData

/// Filter criteria for the Transactions tab. The list re-fetches manually (on appear and after each
/// sync); this struct only carries what the filter sheet collects and what gets persisted between
/// launches. `startDate`/`endDate` are independent optional bounds — a nil end means "no ceiling",
/// so a saved filter never freezes the list at a past date.
struct TransactionFilter: Equatable {
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

// MARK: - Persistence

extension TransactionFilter {
    /// A Codable form of the filter for persisting across launches. Model references can't be
    /// stored directly, so the account and category are kept by `PersistentIdentifier` and
    /// re-resolved against the live store on load. Amounts are strings so `Decimal` round-trips
    /// exactly.
    struct Snapshot: Codable {
        var kind: String
        var reviewState: String
        var accountID: PersistentIdentifier?
        var categoryID: PersistentIdentifier?
        var startDate: Date?
        var endDate: Date?
        var minAmount: String?
        var maxAmount: String?
    }

    var snapshot: Snapshot {
        Snapshot(
            kind: kind.rawValue,
            reviewState: reviewState.rawValue,
            accountID: account?.persistentModelID,
            categoryID: category?.persistentModelID,
            startDate: startDate,
            endDate: endDate,
            minAmount: minAmount.map { NSDecimalNumber(decimal: $0).stringValue },
            maxAmount: maxAmount.map { NSDecimalNumber(decimal: $0).stringValue }
        )
    }

    /// Rebuilds a filter from a saved snapshot, resolving the account/category ids against the
    /// current accounts and categories. A reference whose object was since deleted simply drops to
    /// nil, so a stale saved filter degrades gracefully instead of breaking.
    init(snapshot: Snapshot, accounts: [Account], categories: [Category]) {
        self.init()
        kind = Kind(rawValue: snapshot.kind) ?? .all
        reviewState = ReviewState(rawValue: snapshot.reviewState) ?? .all
        account = snapshot.accountID.flatMap { id in accounts.first { $0.persistentModelID == id } }
        category = snapshot.categoryID.flatMap { id in categories.first { $0.persistentModelID == id } }
        startDate = snapshot.startDate
        endDate = snapshot.endDate
        minAmount = snapshot.minAmount.flatMap { Decimal(string: $0) }
        maxAmount = snapshot.maxAmount.flatMap { Decimal(string: $0) }
    }
}

/// Stores the Transactions tab's active filter in `UserDefaults` so it survives leaving the tab and
/// relaunching the app.
enum TransactionFilterStore {
    private static let key = "transactions.filter"

    static func save(_ snapshot: TransactionFilter.Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> TransactionFilter.Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TransactionFilter.Snapshot.self, from: data)
    }
}
