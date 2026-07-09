import SwiftUI
import SwiftData

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CategoryEditorViewModel?
    @State private var isPresentingNew = false
    @State private var editingCategory: Category?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.categories.isEmpty {
                    EmptyStateView(
                        systemImage: "tag",
                        title: "No Categories",
                        message: "Create categories to organize your transactions and budgets.",
                        actionTitle: "Add Category"
                    ) {
                        isPresentingNew = true
                    }
                } else {
                    List {
                        ForEach(viewModel.topLevelCategories) { category in
                            Section {
                                CategoryRow(category: category) { editingCategory = category }
                                ForEach(viewModel.subcategories(of: category)) { sub in
                                    CategoryRow(category: sub) { editingCategory = sub }
                                        .padding(.leading, 24)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.delete(viewModel.topLevelCategories[index])
                            }
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNew, onDismiss: { viewModel?.load() }) {
            CategoryDetailEditView(category: nil, parentCandidates: viewModel?.topLevelCategories ?? [])
        }
        .sheet(item: $editingCategory, onDismiss: { viewModel?.load() }) { category in
            let candidates = viewModel?.topLevelCategories.filter { $0.persistentModelID != category.persistentModelID } ?? []
            CategoryDetailEditView(category: category, parentCandidates: candidates)
        }
        .task {
            if viewModel == nil { viewModel = CategoryEditorViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }
}

private struct CategoryRow: View {
    let category: Category
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: category.sfSymbolName)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(hex: category.colorHex), in: Circle())
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                if category.isIncome {
                    Text("Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryEditorView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
