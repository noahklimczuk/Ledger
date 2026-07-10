import SwiftUI
import SwiftData

struct AccountEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: Account?
    /// The list's shared view model, so a save updates the same accounts array the list observes
    /// rather than a throwaway one. Optional so previews can present the editor standalone.
    var viewModel: AccountsViewModel? = nil

    @State private var name = ""
    @State private var type: AccountType = .chequing
    @State private var institutionName = ""
    @State private var startingBalanceText = ""

    private var isEditing: Bool { account != nil }

    private var linkedSourceLabel: String {
        account?.externalSourceId == "plaid" ? "Linked to Wealthsimple via Plaid" : "Linked to Wealthsimple"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.displayName, systemImage: type.sfSymbolName).tag(type)
                        }
                    }
                    TextField("Institution (optional)", text: $institutionName)
                }
                Section("Starting Balance") {
                    TextField("0.00", text: $startingBalanceText)
                        .keyboardType(.decimalPad)
                }
                if account?.isLinked == true {
                    Section {
                        Label(linkedSourceLabel, systemImage: "link")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let account else { return }
        name = account.name
        type = account.type
        institutionName = account.institutionName ?? ""
        startingBalanceText = NSDecimalNumber(decimal: account.startingBalance).stringValue
    }

    private func save() {
        let balance = ImportValueParsing.decimal(from: startingBalanceText) ?? 0
        let viewModel = viewModel ?? AccountsViewModel(modelContext: modelContext)
        if let account {
            viewModel.updateAccount(
                account,
                name: name,
                type: type,
                institutionName: institutionName.isEmpty ? nil : institutionName,
                startingBalance: balance
            )
        } else {
            viewModel.addAccount(
                name: name,
                type: type,
                institutionName: institutionName.isEmpty ? nil : institutionName,
                startingBalance: balance
            )
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

#Preview {
    AccountEditView(account: nil)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
