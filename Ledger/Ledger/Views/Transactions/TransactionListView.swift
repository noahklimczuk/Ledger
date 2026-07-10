import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    // @Query keeps this list live: any change to the store — a sync, a manual add/edit, a delete —
    // updates it automatically, so transactions always reflect the latest data without a manual reload.
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)]) private var allTransactions: [Transaction]

    @State private var searchText = ""
    @State private var filter = TransactionListViewModel.Filter()
    @State private var isPresentingNewTransaction = false
    @State private var isPresentingFilters = false

    private var isFiltering: Bool { !searchText.isEmpty || filter.isActive }

    private var transactions: [Transaction] {
        var result = allTransactions

        if let account = filter.account {
            let id = account.persistentModelID
            result = result.filter { $0.account?.persistentModelID == id }
        }
        if let category = filter.category {
            let id = category.persistentModelID
            result = result.filter { $0.category?.persistentModelID == id }
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
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet",
                        title: isFiltering ? "No Matches" : "No Transactions",
                        message: isFiltering
                            ? "Try a different search or filter."
                            : "Add a transaction to start tracking your spending.",
                        actionTitle: isFiltering ? nil : "Add Transaction"
                    ) {
                        isPresentingNewTransaction = true
                    }
                } else {
                    List {
                        ForEach(transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRowView(transaction: transaction)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleReviewed(transaction)
                                } label: {
                                    Label(
                                        transaction.isReviewed ? "Unreview" : "Reviewed",
                                        systemImage: transaction.isReviewed ? "circle" : "checkmark.circle.fill"
                                    )
                                }
                                .tint(.green)
                            }
                            // Long-press menu so delete/review stay reachable where the paged tab
                            // swipe competes with row swipes.
                            .contextMenu {
                                Button {
                                    toggleReviewed(transaction)
                                } label: {
                                    Label(
                                        transaction.isReviewed ? "Mark Unreviewed" : "Mark Reviewed",
                                        systemImage: transaction.isReviewed ? "circle" : "checkmark.circle.fill"
                                    )
                                }
                                Button(role: .destructive) {
                                    delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search merchants")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewTransaction = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { isPresentingFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewTransaction) {
                TransactionEditView(transaction: nil)
            }
            .sheet(isPresented: $isPresentingFilters) {
                TransactionFilterView(filter: $filter)
            }
        }
    }

    private func delete(_ transaction: Transaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
    }

    private func toggleReviewed(_ transaction: Transaction) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        transaction.isReviewed.toggle()
        try? modelContext.save()
    }
}

#Preview {
    TransactionListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
