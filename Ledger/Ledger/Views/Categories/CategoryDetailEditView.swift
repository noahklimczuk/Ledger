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
    @State private var isIncome = false
    @State private var parent: Category?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                    Toggle("Income Category", isOn: $isIncome)
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
        isIncome = category.isIncome
        parent = category.parent
    }

    private func save() {
        let viewModel = CategoryEditorViewModel(modelContext: modelContext)
        if let category {
            viewModel.updateCategory(category, name: name, sfSymbolName: symbol, colorHex: colorHex, isIncome: isIncome)
            category.parent = parent
            try? modelContext.save()
        } else {
            viewModel.addCategory(name: name, sfSymbolName: symbol, colorHex: colorHex, isIncome: isIncome, parent: parent)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
