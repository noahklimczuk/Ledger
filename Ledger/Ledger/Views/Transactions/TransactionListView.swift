import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: TransactionListViewModel?
    @State private var isPresentingNewTransaction = false
    @State private var isPresentingFilters = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.transactions.isEmpty {
                        let isFiltering = !viewModel.searchText.isEmpty || viewModel.filter.isActive
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
                            ForEach(viewModel.transactions) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    TransactionRowView(transaction: transaction)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.delete(transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        viewModel.markReviewed(transaction, reviewed: !transaction.isReviewed)
                                    } label: {
                                        Label(
                                            transaction.isReviewed ? "Unreview" : "Reviewed",
                                            systemImage: transaction.isReviewed ? "circle" : "checkmark.circle.fill"
                                        )
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                        .refreshable { viewModel.load() }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Transactions")
            .searchable(
                text: Binding(get: { viewModel?.searchText ?? "" }, set: { viewModel?.searchText = $0 }),
                prompt: "Search merchants"
            )
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
            .sheet(isPresented: $isPresentingNewTransaction, onDismiss: { viewModel?.load() }) {
                TransactionEditView(transaction: nil)
            }
            .sheet(isPresented: $isPresentingFilters, onDismiss: { viewModel?.load() }) {
                if let viewModel {
                    TransactionFilterView(filter: Binding(get: { viewModel.filter }, set: { viewModel.filter = $0 }))
                }
            }
            .task {
                if viewModel == nil { viewModel = TransactionListViewModel(modelContext: modelContext) }
                viewModel?.load()
            }
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
        }
    }
}

#Preview {
    TransactionListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
