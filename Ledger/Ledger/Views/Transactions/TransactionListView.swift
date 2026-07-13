import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    // Every other data screen re-fetches on `refresh.refreshCount` so a background/foreground sync
    // shows up without re-opening the tab; this list used to rely on a bare live @Query instead,
    // which didn't pick up those sync writes — so it was the one screen stuck on stale data. It now
    // follows the same manual-load pattern: `load()` runs on appear, on every completed refresh, and
    // after any local change (add via the sheet, delete, review toggle).
    @State private var allTransactions: [Transaction] = []
    /// Gates the list behind a loading state until the first fetch lands, so the empty-state card
    /// doesn't flash before the transactions load in.
    @State private var didLoad = false

    @State private var searchText = ""
    /// Whether the toolbar search field is expanded. Collapsed, search is just a magnifying-glass
    /// button sitting beside the filter and plus; tapping it slides the field open in place.
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var filter = TransactionFilter()
    @State private var isPresentingNewTransaction = false
    @State private var isPresentingFilters = false
    /// Guards the one-time restore of the saved filter so it doesn't clobber later edits.
    @State private var didRestoreFilter = false
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
            // Live search doesn't just filter — it re-sorts by how well each row matches, so the
            // closest hits float to the top as the user types: merchants that start with the term
            // first, then merchants that merely contain it, then notes-only matches. Newest wins
            // within a tier, and the explicit date tiebreak keeps the order deterministic (Swift's
            // sort isn't guaranteed stable).
            result = result
                .compactMap { transaction -> (transaction: Transaction, rank: Int)? in
                    let merchant = transaction.merchant.lowercased()
                    if merchant.hasPrefix(needle) { return (transaction, 0) }
                    if merchant.contains(needle) { return (transaction, 1) }
                    if transaction.notes?.lowercased().contains(needle) == true { return (transaction, 2) }
                    return nil
                }
                .sorted { lhs, rhs in
                    lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.transaction.date > rhs.transaction.date
                }
                .map(\.transaction)
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if !didLoad {
                    LoadingView()
                } else if transactions.isEmpty {
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
            // Pull-to-refresh runs a real sync (not just a local re-read); the reload triggered off
            // refreshCount then shows whatever the sync inserted.
            .refreshable { await refresh.refresh(container: modelContext.container) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // A visible filter button (not buried in the overflow menu) that fills in and
                    // tints when any filter is active, so it's obvious filtering is on. Hidden while
                    // the search field is expanded so it has room to slide open.
                    if !isSearchExpanded {
                        Button { isPresentingFilters = true } label: {
                            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .tint(filter.isActive ? .accentColor : nil)
                        .accessibilityLabel(filter.isActive ? "Filters active" : "Filter")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Search sits beside the plus in the same toolbar style: a magnifying-glass
                    // button that slides open into an inline field when tapped.
                    HStack(spacing: 8) {
                        searchControl
                        Button { isPresentingNewTransaction = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .onChange(of: isSearchExpanded) { _, expanded in
                // Focus (raise the keyboard) only once the field actually exists in the hierarchy.
                if expanded { isSearchFocused = true }
            }
            .onChange(of: isSearchFocused) { _, focused in
                // Tapping away from an empty field tidies it back into the button.
                if !focused && searchText.isEmpty { collapseSearch() }
            }
            .sheet(isPresented: $isPresentingNewTransaction, onDismiss: load) {
                TransactionEditView(transaction: nil)
            }
            .sheet(isPresented: $isPresentingFilters) {
                TransactionFilterView(filter: $filter)
            }
            // Load the transactions, then restore the saved filter once. Accounts/categories are
            // fetched synchronously here so resolving the saved references can't drop a valid saved
            // account to nil. The filter restore is guarded to run only on first appearance.
            .task {
                load()
                guard !didRestoreFilter else { return }
                didRestoreFilter = true
                guard let snapshot = TransactionFilterStore.load() else { return }
                let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
                let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
                filter = TransactionFilter(snapshot: snapshot, accounts: accounts, categories: categories)
            }
            // Re-fetch once a background refresh (sync + categorize) finishes, so freshly imported
            // transactions appear without needing to re-open the tab — matching every other screen.
            .onChange(of: refresh.refreshCount) { _, _ in load() }
            // Persist every change (apply, reset) so the filter survives leaving the tab and
            // relaunching. Skipped until the initial restore has run, so it can't save over the
            // saved value with the default before it's loaded.
            .onChange(of: filter) { _, newValue in
                guard didRestoreFilter else { return }
                TransactionFilterStore.save(newValue.snapshot)
            }
        }
    }

    // MARK: - Search

    /// The toolbar search: a magnifying-glass button that slides open into an inline, capsule-shaped
    /// field (matching the app's material pill style) and tucks back away when cleared.
    @ViewBuilder
    private var searchControl: some View {
        if isSearchExpanded {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Search merchants", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(width: 150)
                Button {
                    // First tap clears the text (keeping the field open to keep typing); an empty
                    // field's tap collapses it back to the button.
                    if searchText.isEmpty {
                        collapseSearch()
                    } else {
                        searchText = ""
                        isSearchFocused = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(searchText.isEmpty ? "Close search" : "Clear search")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isSearchExpanded = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search")
        }
    }

    private func collapseSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isSearchExpanded = false
        }
        isSearchFocused = false
        searchText = ""
    }

    /// Re-reads every transaction, newest first. The view's computed `transactions` then applies the
    /// active search, filters, and 12-month window on top.
    private func load() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        allTransactions = (try? modelContext.fetch(descriptor)) ?? []
        didLoad = true
    }

    private func delete(_ transaction: Transaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
        load()
    }

    private func toggleReviewed(_ transaction: Transaction) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        transaction.isReviewed.toggle()
        try? modelContext.save()
        load()
    }
}

#Preview {
    TransactionListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
