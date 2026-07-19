import SwiftUI
import SwiftData

struct TransactionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction?
    @State private var viewModel: TransactionEditViewModel?

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var debts: [Debt] = []

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    Form {
                        Section("Details") {
                            Picker("Type", selection: Binding(get: { viewModel.direction }, set: { viewModel.direction = $0 })) {
                                ForEach(TransactionEditViewModel.Direction.allCases) { direction in
                                    Text(direction.label).tag(direction)
                                }
                            }
                            .pickerStyle(.segmented)
                            TextField("Merchant", text: Binding(get: { viewModel.merchant }, set: { viewModel.merchant = $0 }))
                            TextField("Amount", text: Binding(get: { viewModel.amountText }, set: { viewModel.amountText = $0 }))
                                .keyboardType(.decimalPad)
                            DatePicker(
                                "Date",
                                selection: Binding(get: { viewModel.date }, set: { viewModel.date = $0 }),
                                displayedComponents: .date
                            )
                        }
                        Section("Account") {
                            Picker("Account", selection: Binding(get: { viewModel.account }, set: { viewModel.account = $0 })) {
                                Text("Select an account").tag(Account?.none)
                                ForEach(accounts) { account in
                                    Text(account.name).tag(Account?.some(account))
                                }
                            }
                        }
                        Section("Category") {
                            if viewModel.splits.isEmpty {
                                Picker("Category", selection: Binding(get: { viewModel.category }, set: { viewModel.category = $0 })) {
                                    Text("Uncategorized").tag(Category?.none)
                                    ForEach(categories) { category in
                                        Label(category.name, systemImage: category.sfSymbolName)
                                            .foregroundStyle(Color(hex: category.colorHex))
                                            .tag(Category?.some(category))
                                    }
                                }
                            } else {
                                Text("Categorized via splits below")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !debts.isEmpty {
                            Section {
                                Picker("Debt", selection: Binding(get: { viewModel.debt }, set: { viewModel.debt = $0 })) {
                                    Text("None").tag(Debt?.none)
                                    ForEach(debts) { debt in
                                        Label(debt.name, systemImage: debt.kind.sfSymbolName)
                                            .tag(Debt?.some(debt))
                                    }
                                }
                            } header: {
                                Text("Debt")
                            } footer: {
                                if viewModel.debt != nil && !viewModel.isEditing {
                                    Text("This new transaction will be applied to the debt's balance. Editing it later won't change the balance again.")
                                }
                            }
                        }
                        Section("Split") {
                            SplitEditorView(viewModel: viewModel, categories: categories)
                        }
                        Section("Notes") {
                            TextField(
                                "Notes (optional)",
                                text: Binding(get: { viewModel.notes }, set: { viewModel.notes = $0 }),
                                axis: .vertical
                            )
                        }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .accent(.transactions)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel?.save()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(viewModel?.canSave != true)
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = TransactionEditViewModel(modelContext: modelContext, transaction: transaction)
                }
                accounts = (try? modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))) ?? []
                categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
                // Only active (non-archived) debts are assignable, plus whatever debt an existing
                // transaction already points at (even if since archived) so its selection still shows.
                let activeDebts = (try? modelContext.fetch(FetchDescriptor<Debt>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.name)]))) ?? []
                if let current = viewModel?.debt, !activeDebts.contains(where: { $0.persistentModelID == current.persistentModelID }) {
                    debts = activeDebts + [current]
                } else {
                    debts = activeDebts
                }
                if viewModel?.account == nil, accounts.count == 1 {
                    viewModel?.account = accounts.first
                }
            }
        }
    }
}

#Preview {
    TransactionEditView(transaction: nil)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
