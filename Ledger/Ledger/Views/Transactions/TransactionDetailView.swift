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
                metaCard
                if isSplit {
                    splitsCard
                }
                insightFooter
                actionButtons
            }
            .padding()
        }
        .accentWash(.transactions)
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
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appSurface)
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.bloomShadow, radius: 15, x: 6, y: 6)
                    .shadow(color: Color.bloomHighlight, radius: 10, x: -4, y: -4)

                Text(transaction.category?.displayIcon ?? BloomEmoji.merchantEmoji(name: transaction.merchant))
                    .font(.system(size: 26))
                    .foregroundStyle(heroIconColor)
            }

            Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                .font(.appMoney)
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Palette.income)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(transaction.merchant)
                .font(.appHeadline.weight(.heavy))
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Text("🕓")
                    .font(.system(size: 12))
                Text(DateFormatting.medium(transaction.date))
                    .font(.appCaption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var heroIconColor: Color {
        if let category = transaction.category {
            return Color(hex: category.colorHex)
        }
        return .gray
    }

    // MARK: - Category

    private var categoryRow: some View {
        HStack(spacing: 14) {
            Text("Category")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.3)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Menu {
                Button("Uncategorized") { applyCategory(nil) }
                ForEach(categories, id: \.persistentModelID) { category in
                    Button { applyCategory(category) } label: {
                        Text("\(category.displayIcon)  \(category.name)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    let category = transaction.category
                    Text(category?.displayIcon ?? "❓")
                        .font(.system(size: 14))
                    Text(category?.name ?? "Uncategorized")
                        .font(.appCaption.weight(.heavy))
                        .lineLimit(1)
                    Text("›")
                        .font(AppFont.scaled(12, relativeTo: .caption2, weight: .bold))
                }
                .foregroundStyle(Palette.greenDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.green.opacity(0.15), in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Meta

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailMetaRow(icon: transaction.account?.displayIcon ?? "🏦", isEmoji: true, label: "Account", value: transaction.account?.name ?? "—")
            Divider().padding(.leading, 38)
            if !isSplit {
                categoryRow
                Divider().padding(.leading, 38)
            }
            DetailMetaRow(
                icon: transaction.isReviewed ? "✓" : "⚠️",
                isEmoji: true,
                label: "Status",
                value: transaction.isReviewed ? "Reviewed" : "Needs review",
                tint: transaction.isReviewed ? Palette.greenDeep : Palette.coral
            )
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Splits

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Split across \(transaction.splits.count) categor\(transaction.splits.count == 1 ? "y" : "ies")")
                .font(.appHeadline.weight(.heavy))

            VStack(spacing: 0) {
                ForEach(Array(transaction.splits.enumerated()), id: \.element.persistentModelID) { index, split in
                    if index > 0 {
                        Divider().padding(.leading, 24)
                    }
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(split.category.map { Color(hex: $0.colorHex) } ?? .gray)
                            .frame(width: 10, height: 10)

                        Text(split.category?.name ?? "Uncategorized")
                            .font(.appBodyMedium.weight(.semibold))

                        Spacer()
                        Text(CurrencyFormatter.string(from: abs(split.amount), currencyCode: transaction.account?.currencyCode ?? "CAD"))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("💡")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.peri)
                    .padding(.top, 2)

                Text("Changing the category here also ")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                + Text("teaches Ledger")
                    .font(.appSubheadline.weight(.heavy))
                    .foregroundStyle(Palette.greenDeep)
                + Text(" to auto-file future \(transaction.merchant) charges.")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
            }

            if !relatedInsights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(relatedInsights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Text("💡")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.peri)
                                .padding(.top, 4)
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
        .background(
            ZStack {
                Color.appSurface
                LinearGradient(
                    colors: [Palette.peri.opacity(0.10), Palette.peri.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Palette.peri.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            AccentButton(title: "Edit transaction", accent: .dashboard) {
                isEditing = true
            }

            Button { isConfirmingDelete = true } label: {
                Text("Delete")
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

private struct DetailMetaRow: View {
    let icon: String
    var isEmoji: Bool = false
    let label: String
    let value: String
    var tint: Color? = nil

    private var iconView: some View {
        Group {
            if isEmoji {
                Text(icon)
                    .font(.system(size: 17))
            } else {
                Image(systemName: icon)
                    .font(AppFont.scaled(15, relativeTo: .subheadline, weight: .bold))
            }
        }
        .foregroundStyle(tint ?? Color.secondary)
    }

    var body: some View {
        HStack(spacing: 14) {
            iconView
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.appCaption2.weight(.heavy))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.appBodyMedium.weight(.semibold))
                    .foregroundStyle(tint ?? Color.primary)
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
