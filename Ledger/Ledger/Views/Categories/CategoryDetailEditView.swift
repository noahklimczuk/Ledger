import SwiftUI
import SwiftData

struct CategoryDetailEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let category: Category?
    let parentCandidates: [Category]

    @State private var name = ""
    @State private var symbol = "tag.fill"
    @State private var colorHex = "#8E8E93"
    @State private var kind: CategoryKind = .expense
    @State private var parent: Category?

    /// Mutually exclusive category kind. Transfers are excluded from income and spending totals.
    private enum CategoryKind: String, CaseIterable, Identifiable {
        case expense, income, transfer
        var id: String { rawValue }
        var label: String {
            switch self {
            case .expense: "Expense"
            case .income: "Income"
            case .transfer: "Transfer"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(CategoryKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                } header: {
                    Text("Name")
                } footer: {
                    if kind == .transfer {
                        Text("Transfers move money between your own accounts, so they don't count as income or spending.")
                    }
                }
                Section("Parent") {
                    Picker("Parent Category", selection: $parent) {
                        Text("None (top-level)").tag(Category?.none)
                        ForEach(parentCandidates) { candidate in
                            Text(candidate.name).tag(Category?.some(candidate))
                        }
                    }
                }
                Section("Icon") {
                    IconPickerView(selection: $symbol)
                }
                Section("Color") {
                    ColorPickerGridView(selectionHex: $colorHex)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
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
        guard let category else { return }
        name = category.name
        symbol = category.sfSymbolName
        colorHex = category.colorHex
        kind = category.isTransfer ? .transfer : (category.isIncome ? .income : .expense)
        parent = category.parent
    }

    private func save() {
        let viewModel = CategoryEditorViewModel(modelContext: modelContext)
        let isIncome = kind == .income
        let isTransfer = kind == .transfer
        if let category {
            viewModel.updateCategory(category, name: name, sfSymbolName: symbol, colorHex: colorHex, isIncome: isIncome, isTransfer: isTransfer)
            category.parent = parent
            try? modelContext.save()
        } else {
            viewModel.addCategory(name: name, sfSymbolName: symbol, colorHex: colorHex, isIncome: isIncome, isTransfer: isTransfer, parent: parent)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
