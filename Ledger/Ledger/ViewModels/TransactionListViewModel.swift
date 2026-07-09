import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TransactionListViewModel {
    struct Filter {
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

    private(set) var transactions: [Transaction] = []
    var searchText: String = "" { didSet { applyFilters() } }
    var filter = Filter() { didSet { applyFilters() } }

    private var allTransactions: [Transaction] = []
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func load() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        allTransactions = (try? modelContext.fetch(descriptor)) ?? []
        applyFilters()
    }

    private func applyFilters() {
        var result = allTransactions

        if let account = filter.account {
            let accountId = account.persistentModelID
            result = result.filter { $0.account?.persistentModelID == accountId }
        }
        if let category = filter.category {
            let categoryId = category.persistentModelID
            result = result.filter { $0.category?.persistentModelID == categoryId }
        }
        if let startDate = filter.startDate {
            result = result.filter { $0.date >= startDate }
        }
        if let endDate = filter.endDate {
            result = result.filter { $0.date <= endDate }
        }
        if let minAmount = filter.minAmount {
            result = result.filter { abs($0.amount) >= minAmount }
        }
        if let maxAmount = filter.maxAmount {
            result = result.filter { abs($0.amount) <= maxAmount }
        }

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            result = result.filter {
                $0.merchant.lowercased().contains(needle) || ($0.notes?.lowercased().contains(needle) ?? false)
            }
        }

        transactions = result
    }

    func markReviewed(_ transaction: Transaction, reviewed: Bool = true) {
        transaction.isReviewed = reviewed
        try? modelContext.save()
    }

    func delete(_ transaction: Transaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
        load()
    }
}
