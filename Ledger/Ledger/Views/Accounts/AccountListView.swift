import SwiftUI
import SwiftData

struct AccountListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: AccountsViewModel?
    @State private var isPresentingNewAccount = false
    @State private var editingAccount: Account?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.accounts.isEmpty {
                        EmptyStateView(
                            systemImage: "banknote",
                            title: "No Accounts",
                            message: "Add a chequing, savings, credit, or investment account to get started.",
                            actionTitle: "Add Account"
                        ) {
                            isPresentingNewAccount = true
                        }
                    } else {
                        List {
                            ForEach(viewModel.accounts) { account in
                                // Read the displayed values here, up front, into a plain snapshot.
                                // If this account is deleted, SwiftUI may re-render the outgoing row
                                // during its removal animation; a snapshot means that render never
                                // touches the now-invalidated model (which would crash reading
                                // `currentBalance`/`startingBalance`).
                                Button { editingAccount = account } label: {
                                    AccountRow(account: AccountRow.Snapshot(account))
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        viewModel.remove(account)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        // Pull-to-refresh runs a real sync; the refreshCount observer below then
                        // reloads the VM with the new balances.
                        .refreshable { await refresh.refresh(container: modelContext.container) }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewAccount = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingNewAccount, onDismiss: { viewModel?.load() }) {
                AccountEditView(account: nil, viewModel: viewModel)
            }
            .sheet(item: $editingAccount, onDismiss: { viewModel?.load() }) { account in
                AccountEditView(account: account, viewModel: viewModel)
            }
            .task {
                if viewModel == nil { viewModel = AccountsViewModel(modelContext: modelContext) }
                viewModel?.load()
            }
            .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
        }
    }
}

private struct AccountRow: View {
    /// Plain, already-read values for one account row. Reading them once, up front, keeps the row
    /// from touching the live SwiftData model — which crashes if the model has since been deleted.
    struct Snapshot {
        let symbol: String
        let name: String
        let institutionName: String?
        let balanceText: String

        init(_ account: Account) {
            symbol = account.type.sfSymbolName
            name = account.name
            institutionName = account.institutionName
            balanceText = CurrencyFormatter.string(from: account.currentBalance, currencyCode: account.currencyCode)
        }
    }

    let account: Snapshot

    var body: some View {
        HStack {
            Image(systemName: account.symbol)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.tint, in: Circle())
            VStack(alignment: .leading) {
                Text(account.name)
                if let institutionName = account.institutionName {
                    Text(institutionName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(account.balanceText)
                .fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    AccountListView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
