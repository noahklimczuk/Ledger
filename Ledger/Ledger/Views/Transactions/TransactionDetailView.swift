import SwiftUI
import SwiftData

/// Bloom transaction detail: a centred hero amount, merchant, category chip, clay meta rows, split
/// list, an insight footer, and Edit / Delete actions.
struct TransactionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction

    @State private var categories: [Category] = []
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var bulkCandidate: BulkCategoryCandidate?
    @State private var relatedInsights: [String] = []

    private struct BulkCategoryCandidate: Identifiable {
        let id = UUID()
        let category: Category
        let count: Int
    }

    private var isSplit: Bool { !transaction.splits.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                heroSection
                if !isSplit {
                    categorySection
                }
                metaCard
                if isSplit {
                    splitsCard
                }
                insightFooter
                actionButtons
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .accent(.transactions)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: loadCategories) {
            TransactionEditView(transaction: transaction)
        }
        .confirmationDialog(
            "Apply to Similar Transactions?",
            isPresented: Binding(get: { bulkCandidate != nil }, set: { if !$0 { bulkCandidate = nil } }),
            titleVisibility: .visible,
            presenting: bulkCandidate
        ) { candidate in
            Button("Change All \(candidate.count)") { applyToAllMatching(candidate.category) }
            Button("Only This One", role: .cancel) { }
        } message: { candidate in
            Text("There \(candidate.count == 1 ? "is" : "are") \(candidate.count) other transaction\(candidate.count == 1 ? "" : "s") from “\(transaction.merchant)”. Set \(candidate.count == 1 ? "it" : "them") to “\(candidate.category.name)” too?")
        }
        .alert("Delete transaction?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { deleteTransaction() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the transaction from your history. This can't be undone.")
        }
        .task(id: transaction.persistentModelID) {
            loadCategories()
            relatedInsights = gatherInsights()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            Text(transaction.merchant)
                .font(.appTitle3.weight(.heavy))
                .multilineTextAlignment(.center)

            Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Palette.income)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(DateFormatting.relativeDay(transaction.date))
                    .font(.appCaption.weight(.bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appSurface, in: Capsule())
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category chip

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    DetailCategoryChip(
                        name: "Uncategorized",
                        systemImage: "questionmark.circle.fill",
                        color: .gray,
                        isSelected: transaction.category == nil
                    ) {
                        applyCategory(nil)
                    }

                    ForEach(categories, id: \.persistentModelID) { category in
                        DetailCategoryChip(
                            name: category.name,
                            systemImage: category.sfSymbolName,
                            color: Color(hex: category.colorHex),
                            isSelected: transaction.category?.persistentModelID == category.persistentModelID
                        ) {
                            applyCategory(category)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Meta

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailMetaRow(icon: transaction.account?.type.sfSymbolName ?? "banknote", label: "Account", value: transaction.account?.name ?? "—")
            Divider().padding(.leading, 38)
            DetailMetaRow(icon: "calendar", label: "Date", value: DateFormatting.medium(transaction.date))
            Divider().padding(.leading, 38)
            DetailMetaRow(icon: transaction.isReviewed ? "checkmark.circle.fill" : "exclamationmark.circle.fill", label: "Status", value: transaction.isReviewed ? "Reviewed" : "Needs review")
            Divider().padding(.leading, 38)
            DetailMetaRow(icon: "arrow.down.circle", label: "Source", value: transaction.sourceKind.displayName)
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Splits

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Split")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(transaction.splits.enumerated()), id: \.element.persistentModelID) { index, split in
                    if index > 0 {
                        Divider().padding(.leading, 24)
                    }
                    HStack {
                        Text(split.category?.name ?? "Uncategorized")
                            .font(.appBodyMedium.weight(.semibold))
                        Spacer()
                        Text(CurrencyFormatter.string(from: split.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                            .font(.appBody.weight(.heavy))
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Insights

    private var insightFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.appCaption.weight(.bold))
                    .foregroundStyle(Palette.amberDeep)
                Text("Ask Ledger")
                    .font(.appCaption.weight(.black))
                    .foregroundStyle(Palette.amberDeep)
            }

            if relatedInsights.isEmpty {
                Text("No insights for this transaction.")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(relatedInsights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "smallcircle.filled.circle")
                                .font(.system(size: 7))
                                .foregroundStyle(Palette.amber)
                                .padding(.top, 6)
                            Text(insight)
                                .font(.appSubheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.amber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Palette.amber.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button { isEditing = true } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.appSubheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            Button { isConfirmingDelete = true } label: {
                Label("Delete", systemImage: "trash")
                    .font(.appSubheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(Palette.coral)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Logic

    private func applyCategory(_ category: Category?) {
        guard !isSplit else { return }
        transaction.category = category
        UISelectionFeedbackGenerator().selectionChanged()
        guard let category else {
            try? modelContext.save()
            return
        }
        let categorizer = CategorizationService(modelContext: modelContext)
        categorizer.learn(merchant: transaction.merchant, category: category)
        try? modelContext.save()
        let others = categorizer.otherTransactions(matching: transaction.merchant, excluding: transaction)
        if !others.isEmpty {
            bulkCandidate = BulkCategoryCandidate(category: category, count: others.count)
        }
        relatedInsights = gatherInsights()
    }

    private func applyToAllMatching(_ category: Category) {
        CategorizationService(modelContext: modelContext)
            .assignCategory(category, toAllMatching: transaction.merchant)
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func deleteTransaction() {
        modelContext.delete(transaction)
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        dismiss()
    }

    private func loadCategories() {
        categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))) ?? []
    }

    private func gatherInsights() -> [String] {
        var insights: [String] = []
        if transaction.amount < -100 {
            insights.append("This is one of your larger expenses this month.")
        }
        if let category = transaction.category, category.isTransfer {
            insights.append("Transfers move money between your own accounts and don't affect spending or income.")
        }
        if transaction.isSplit {
            insights.append("Split transactions divide one purchase across multiple categories.")
        }
        if !transaction.isReviewed {
            insights.append("This transaction hasn't been reviewed yet.")
        }
        return insights
    }
}

// MARK: - Supporting views

private struct DetailCategoryChip: View {
    let name: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? .white : color)
                Text(name)
                    .font(.appCaption.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Color.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? color.opacity(0.92) : Color.appSurface, in: Capsule())
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.appHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DetailMetaRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.appCaption2.weight(.heavy))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.appBodyMedium.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        TransactionDetailView(transaction: Transaction(date: .now, merchant: "Preview", amount: -12.34, account: Account(name: "Chequing", type: .chequing)))
    }
}
