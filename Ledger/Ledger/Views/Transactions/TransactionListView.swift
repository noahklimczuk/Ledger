import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var allTransactions: [Transaction] = []
    @State private var didLoad = false

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var filter = TransactionFilter()
    @State private var isPresentingNewTransaction = false
    @State private var isPresentingFilters = false
    @State private var didRestoreFilter = false
    @State private var showAllHistory = false

    @State private var visibleTransactions: [Transaction] = []
    @State private var hasHiddenOlderHistory = false

    private var isFiltering: Bool { !searchText.isEmpty || filter.isActive }

    private static var twelveMonthsAgo: Date? {
        Calendar.current.date(byAdding: .month, value: -12, to: .now)
    }

    private var effectiveStartDate: Date? {
        if let start = filter.startDate { return start }
        return showAllHistory ? nil : Self.twelveMonthsAgo
    }

    var body: some View {
        NavigationStack {
            Group {
                if !didLoad {
                    LoadingView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                            searchAndFiltersCard
                            if visibleTransactions.isEmpty {
                                emptyStateCard
                            } else {
                                spendingBreakdownCard
                                transactionListGrouped
                                showAllHistoryButton
                            }
                        }
                        .padding()
                    }
                    .refreshable { await refresh.refresh(container: modelContext.container) }
                }
            }
            .navigationTitle("")
            .accentWash(.transactions)
            .accent(.transactions)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Activity · \(monthLabel(.now))")
                        .font(.appHeadline.weight(.heavy))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresentingNewTransaction = true } label: {
                        Text("+ Add")
                            .font(.appCaption.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [Palette.peach, Palette.amber],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule(style: .continuous)
                            )
                            .shadow(color: Palette.peach.opacity(0.4), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Transaction")
                }
            }
            .sheet(isPresented: $isPresentingNewTransaction, onDismiss: load) {
                TransactionEditView(transaction: nil)
            }
            .sheet(isPresented: $isPresentingFilters) {
                TransactionFilterView(filter: $filter)
            }
            .task {
                load()
                guard !didRestoreFilter else { return }
                didRestoreFilter = true
                guard let snapshot = TransactionFilterStore.load() else { return }
                let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
                let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
                filter = TransactionFilter(snapshot: snapshot, accounts: accounts, categories: categories)
            }
            .onChange(of: refresh.refreshCount) { _, _ in load() }
            .onChange(of: searchText) { _, _ in recompute() }
            .onChange(of: showAllHistory) { _, _ in recompute() }
            .onChange(of: filter) { _, newValue in
                recompute()
                guard didRestoreFilter else { return }
                TransactionFilterStore.save(newValue.snapshot)
            }
            .onChange(of: isSearchFocused) { _, focused in
                if !focused { dismissKeyboard() }
            }
        }
    }

    // MARK: - Header

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }

    // MARK: - Search + filters

    private var searchAndFiltersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchBar(
                text: $searchText,
                placeholder: "Search merchants",
                isFocused: $isSearchFocused,
                onCancel: { clearSearch() }
            )
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    isSelected: filter.kind == .all && filter.reviewState == .all
                ) {
                    filter.kind = .all
                    filter.reviewState = .all
                }
                FilterChip(
                    title: "Expenses",
                    isSelected: filter.kind == .expenses && filter.reviewState == .all
                ) {
                    filter.kind = .expenses
                    filter.reviewState = .all
                }
                FilterChip(
                    title: "Income",
                    isSelected: filter.kind == .income && filter.reviewState == .all
                ) {
                    filter.kind = .income
                    filter.reviewState = .all
                }
                FilterChip(
                    title: "Needs review",
                    isSelected: filter.reviewState == .needsReview
                ) {
                    filter.reviewState = filter.reviewState == .needsReview ? .all : .needsReview
                }
                Spacer()
            }
            Button { isPresentingFilters = true } label: {
                HStack(spacing: 4) {
                    Text(filter.isActive ? "Filters active" : "More filters")
                        .font(.appCaption.weight(.heavy))
                    Text("›")
                        .font(.appCaption.weight(.bold))
                }
                .foregroundStyle(filter.isActive ? Accent.wellness.deep : .secondary)
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func clearSearch() {
        searchText = ""
        isSearchFocused = false
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private struct FilterChip: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.appCaption2.weight(.heavy))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Accent.wellness.base)
                            : AnyShapeStyle(Color.appSurface),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : Color.appHairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Spending breakdown

    private var spendingBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending breakdown")
                .font(.appCaption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            InteractiveDonutChart(
                segments: breakdownSegments,
                centerCaption: "Total spent",
                showLegend: true,
                isInteractive: false
            )
        }
        .card()
    }

    private var breakdownSegments: [DonutSegment] {
        var totals: [String: (amount: Decimal, color: Color, category: Category?)] = [:]
        for transaction in visibleTransactions {
            let entries: [(category: Category?, amount: Decimal)] = transaction.isSplit
                ? transaction.splits.map { ($0.category, $0.amount) }
                : [(transaction.category, transaction.amount)]
            for (category, amount) in entries {
                guard amount < 0, category?.isTransfer != true else { continue }
                let name = category?.name ?? "Uncategorized"
                let color = category.map { Color(hex: $0.colorHex) } ?? Color.ink3
                let existing = totals[name] ?? (0, color, category)
                totals[name] = (existing.amount + (-amount), color, existing.category ?? category)
            }
        }

        let sorted = totals
            .map { DonutSegment(id: $0.key, label: $0.key, value: $0.value.amount, color: $0.value.color, isSelectable: false) }
            .sorted { $0.value > $1.value }

        if sorted.count <= 5 { return sorted }
        let top = Array(sorted.prefix(4))
        let other = sorted.dropFirst(4).reduce(Decimal(0)) { $0 + $1.value }
        return top + [DonutSegment(id: "Other", label: "Other", value: other, color: Color.ink3, isSelectable: false)]
    }

    // MARK: - Grouped transaction list

    private var transactionListGrouped: some View {
        LazyVStack(pinnedViews: [.sectionHeaders], spacing: Theme.sectionSpacing) {
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                if let txs = grouped[day] {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(txs) { transaction in
                                rowView(transaction)
                                if transaction.persistentModelID != txs.last?.persistentModelID {
                                    TransactionRowDivider()
                                }
                            }
                        }
                    } header: {
                        dayHeader(day, transactions: txs)
                    }
                }
            }
        }
    }

    private var grouped: [Date: [Transaction]] {
        let calendar = Calendar.current
        return Dictionary(grouping: visibleTransactions) { calendar.startOfDay(for: $0.date) }
    }

    private func dayHeader(_ day: Date, transactions: [Transaction]) -> some View {
        let total = transactions
            .filter { $0.category?.isTransfer != true }
            .reduce(Decimal(0)) { $0 + ($1.amount < 0 ? -$1.amount : 0) }
        return HStack {
            Text(DateFormatting.relativeDay(day))
                .font(.appCaption2.weight(.heavy))
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            Text(CurrencyFormatter.string(from: total))
                .font(.appCaption.weight(.heavy))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appSurface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rowView(_ transaction: Transaction) -> some View {
        NavigationLink {
            TransactionDetailView(transaction: transaction)
        } label: {
            TransactionRowView(transaction: transaction)
                .padding(.vertical, 6)
        }
        .buttonStyle(.pressable)
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

    private var showAllHistoryButton: some View {
        Group {
            if hasHiddenOlderHistory {
                Button {
                    withAnimation { showAllHistory = true }
                } label: {
                    HStack {
                        Spacer()
                        Text("Show All History")
                            .font(.appSubheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Color.appHairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateCard: some View {
        VStack(spacing: 14) {
            BloomRowIcon(emoji: "📋", size: 64)
            Text(isFiltering ? "No Matches" : "No Transactions")
                .font(.appTitle3.weight(.heavy))
            Text(isFiltering ? "Try a different search or filter." : "Add a transaction to start tracking your spending.")
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !isFiltering {
                Button { isPresentingNewTransaction = true } label: {
                    Text("Add Transaction")
                        .font(.appCaption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Accent.wellness.base, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Data

    private func load() {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        allTransactions = (try? modelContext.fetch(descriptor)) ?? []
        didLoad = true
        recompute()
    }

    private func recompute() {
        visibleTransactions = computeVisibleTransactions()
        hasHiddenOlderHistory = computeHasHiddenOlderHistory()
    }

    private func computeHasHiddenOlderHistory() -> Bool {
        guard !showAllHistory, filter.startDate == nil, let floor = Self.twelveMonthsAgo else { return false }
        return allTransactions.contains { $0.date < floor }
    }

    private func computeVisibleTransactions() -> [Transaction] {
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
            let endExclusive = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
            result = result.filter { $0.date < endExclusive }
        }
        if let minAmount = filter.minAmount {
            result = result.filter { abs($0.amount) >= minAmount }
        }
        if let maxAmount = filter.maxAmount {
            result = result.filter { abs($0.amount) <= maxAmount }
        }

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
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

    private func delete(_ transaction: Transaction) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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

private struct TransactionRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.appHairline)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

#Preview {
    TransactionListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
