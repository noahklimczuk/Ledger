import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    // @Query keeps this list live: any change to the store — a sync, a manual add/edit, a delete —
    // updates it automatically, so transactions always reflect the latest data without a manual reload.
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)]) private var allTransactions: [Transaction]

    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var isPresentingNewTransaction = false
    @State private var isPresentingFilters = false
    /// The list defaults to the last 12 months rather than the account's whole history. This opts
    /// out of that window to show everything.
    @State private var showAllHistory = false

    private var isFiltering: Bool { !searchText.isEmpty || filter.isActive }

    /// Floor for the default 12-month window (nil only if date math somehow fails).
    private static var twelveMonthsAgo: Date? {
        Calendar.current.date(byAdding: .month, value: -12, to: .now)
    }

    /// The start date actually applied: an explicit Filters start date wins; otherwise the 12-month
    /// window, unless the user chose to show all history.
    private var effectiveStartDate: Date? {
        if let start = filter.startDate { return start }
        return showAllHistory ? nil : Self.twelveMonthsAgo
    }

    /// True when the default 12-month window is hiding older transactions the user could still reach.
    private var hasHiddenOlderHistory: Bool {
        guard !showAllHistory, filter.startDate == nil, let floor = Self.twelveMonthsAgo else { return false }
        return allTransactions.contains { $0.date < floor }
    }

    private var transactions: [Transaction] {
        var result = allTransactions

        switch filter.kind {
        case .all: break
        case .expenses: result = result.filter { $0.amount < 0 }
        case .income: result = result.filter { $0.amount >= 0 }
        }
        switch filter.reviewState {
        case .all: break
        case .needsReview: result = result.filter { !$0.isReviewed }
        case .reviewed: result = result.filter(\.isReviewed)
        }
        if let account = filter.account {
            let id = account.persistentModelID
            result = result.filter { $0.account?.persistentModelID == id }
        }
        if let category = filter.category {
            let id = category.persistentModelID
            result = result.filter { $0.category?.persistentModelID == id }
        }
        if let startDate = effectiveStartDate {
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
                    if hasHiddenOlderHistory && !isFiltering {
                        EmptyStateView(
                            systemImage: "clock.arrow.circlepath",
                            title: "Nothing Recent",
                            message: "No transactions in the last 12 months.",
                            actionTitle: "Show All History"
                        ) {
                            withAnimation { showAllHistory = true }
                        }
                    } else {
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

                        if hasHiddenOlderHistory {
                            Button {
                                withAnimation { showAllHistory = true }
                            } label: {
                                Label("Show All History", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            // Pull-to-refresh runs a real sync (not just a local re-read); the live @Query then
            // shows whatever the sync inserted.
            .refreshable { await refresh.refresh(container: modelContext.container) }
            .searchable(text: $searchText, prompt: "Search merchants")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // A visible filter button (not buried in the overflow menu) that fills in and
                    // tints when any filter is active, so it's obvious filtering is on.
                    Button { isPresentingFilters = true } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .tint(filter.isActive ? .accentColor : nil)
                    .accessibilityLabel(filter.isActive ? "Filters active" : "Filter")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewTransaction = true } label: {
                        Image(systemName: "plus")
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
        .environment(AppRefreshCoordinator())
}
