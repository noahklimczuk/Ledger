import SwiftUI
import SwiftData

/// Pushed detail screen for a single transaction. Shows the merchant, amount, date, account, and —
/// front and centre — its current category, which can be changed right here. Changing the category
/// also teaches the auto-categorization rule (same as the editor), so future transactions from the
/// same merchant pick it up. A toolbar "Edit" opens the full editor for everything else.
struct TransactionDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let transaction: Transaction

    @State private var categories: [Category] = []
    @State private var isEditing = false

    private var isSplit: Bool { !transaction.splits.isEmpty }

    var body: some View {
        Form {
            headerSection
            categorySection
            detailsSection
            if let notes = transaction.notes, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: loadCategories) {
            TransactionEditView(transaction: transaction)
        }
        .task(id: transaction.persistentModelID) { loadCategories() }
        // Pushed screen: swiping should go back, not drag to the next tab.
        .disablesTabSwipe()
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(transaction.merchant)
                    .font(.title3.bold())
                Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(transaction.amount < 0 ? Color.primary : Color.green)
                Text(DateFormatting.medium(transaction.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        Section("Category") {
            currentCategoryRow
            if isSplit {
                Text("This transaction is split across categories. Use Edit to change the split.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Change Category", selection: categoryBinding) {
                    Text("Uncategorized").tag(Category?.none)
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.sfSymbolName)
                            .tag(Category?.some(category))
                    }
                }
            }
        }
    }

    private var currentCategoryRow: some View {
        HStack {
            Image(systemName: transaction.category?.sfSymbolName ?? "questionmark.circle")
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(transaction.category.map { Color(hex: $0.colorHex) } ?? .gray, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Current Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(isSplit ? "Split" : (transaction.category?.name ?? "Uncategorized"))
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 2)
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Account", value: transaction.account?.name ?? "—")
            LabeledContent("Date", value: DateFormatting.medium(transaction.date))
            LabeledContent("Status", value: transaction.isReviewed ? "Reviewed" : "Needs review")
            if transaction.sourceKind != .manual {
                LabeledContent("Source", value: transaction.sourceKind.rawValue.uppercased())
            }
            if isSplit {
                ForEach(transaction.splits) { split in
                    LabeledContent(
                        split.category?.name ?? "Uncategorized",
                        value: CurrencyFormatter.string(from: split.amount, currencyCode: transaction.account?.currencyCode ?? "CAD")
                    )
                }
            }
        }
    }

    // MARK: - Category change

    private var categoryBinding: Binding<Category?> {
        Binding(
            get: { transaction.category },
            set: { applyCategory($0) }
        )
    }

    private func applyCategory(_ category: Category?) {
        guard !isSplit else { return }
        transaction.category = category
        // Teach the rule so future transactions from this merchant auto-categorize the same way,
        // and replay it immediately so the merchant's other uncategorized transactions update now.
        if let category {
            let categorizer = CategorizationService(modelContext: modelContext)
            categorizer.learn(merchant: transaction.merchant, category: category)
            categorizer.categorizeAllUncategorized()
        }
        try? modelContext.save()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func loadCategories() {
        categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))) ?? []
    }
}
