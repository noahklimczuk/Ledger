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
                        emoji: "🏷️",
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
                    .scrollContentBackground(.hidden)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Categories")
        .accentWash(.categories)
        .accent(.categories)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Category")
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
            HStack(spacing: 12) {
                BloomRowIcon(emoji: category.displayIcon, size: 34)
                Text(category.name)
                    .font(.appBodyMedium)
                    .foregroundStyle(.primary)
                Spacer()
                if category.isIncome {
                    Chip(text: "Income", color: Palette.income)
                }
            }
        }
        .buttonStyle(.pressable)
        .card()
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

#Preview {
    NavigationStack {
        CategoryEditorView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
