import SwiftUI
import SwiftData

/// Reviewable AI budget proposal for one month. Everything is a *proposal* until the user taps
/// Apply: amounts are editable, categories can be excluded, and cancelling changes nothing.
/// The statistics come from on-device aggregation; the optional Gemini refinement receives the
/// category totals plus recent transaction lines (see `GeminiService`). The plan always includes
/// a monthly savings set-aside proportional to the income-vs-spending gap.
struct BudgetSuggestionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let month: Date

    @State private var viewModel: BudgetSuggestionViewModel?
    @State private var isEditingKey = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    LoadingView(message: "Analyzing your spending…")
                }
            }
            .navigationTitle("Suggested Budget")
            .accent(.budgets)
            .accentWash(.budgets)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel?.apply()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .disabled(viewModel?.canApply != true)
                }
            }
            .task {
                if viewModel == nil {
                    let model = BudgetSuggestionViewModel(modelContext: modelContext, month: month)
                    viewModel = model
                    await model.generate()
                }
            }
            .sheet(isPresented: $isEditingKey, onDismiss: {
                // Re-run so a freshly added key upgrades the proposal in place.
                Task { await viewModel?.generate() }
            }) {
                if let viewModel {
                    apiKeySheet(viewModel)
                }
            }
        }
    }

    // MARK: - Stages

    @ViewBuilder
    private func content(_ viewModel: BudgetSuggestionViewModel) -> some View {
        switch viewModel.stage {
        case .loading:
            LoadingView(message: "Analyzing your spending…")
        case .noData:
            EmptyStateView(
                systemImage: "chart.pie",
                title: "Not Enough History",
                message: "Suggestions are built from your categorized spending. Add or import a month or two of transactions first."
            )
        case .review:
            reviewList(viewModel)
        case .applied:
            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Palette.income.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appDisplay)
                        .foregroundStyle(Palette.income)
                }
                Text("Budget Applied")
                    .font(.appTitle3.weight(.heavy))
                Text("\(viewModel.appliedCount) budget\(viewModel.appliedCount == 1 ? "" : "s") set for \(DateFormatting.monthYear(viewModel.month)).")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accentWash(.budgets)
        }
    }

    private func reviewList(_ viewModel: BudgetSuggestionViewModel) -> some View {
        List {
            Section {
                summaryCard(viewModel)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(viewModel.rows) { row in
                    proposalRow(row, viewModel: viewModel)
                }
            } header: {
                HStack {
                    Text("Proposed Budgets")
                    Spacer()
                    Text("\(viewModel.includedCount) of \(viewModel.rows.count) included")
                }
            }

            Section {
                savingsRow(viewModel)
            } header: {
                Text("Monthly Savings")
            }

            if let aiStatus = viewModel.aiStatus {
                Section {
                    Button {
                        isEditingKey = true
                    } label: {
                        Label(aiStatus, systemImage: viewModel.hasAPIKey ? "exclamationmark.triangle" : "sparkles")
                            .font(.appFootnote)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Pieces

    private func summaryCard(_ viewModel: BudgetSuggestionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient.brand)
                Text("Plan for \(DateFormatting.monthYear(viewModel.month))")
                    .font(.appHeadline)
                Spacer()
                if viewModel.isRefining {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Getting AI suggestions")
                }
            }
            Text(viewModel.planSummary)
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                statTile("Proposed total", value: CurrencyFormatter.string(from: viewModel.totalProposed))
                statTile("Avg. income", value: CurrencyFormatter.string(from: viewModel.averageMonthlyIncome))
                statTile("History", value: "\(viewModel.monthsAnalyzed) mo")
            }
        }
        .card()
        .padding(.top, 4)
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.appCaption2).foregroundStyle(.secondary)
            Text(value)
                .font(.appSubheadline.weight(.semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proposalRow(_ row: BudgetSuggestionViewModel.ProposalRow, viewModel: BudgetSuggestionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BloomRowIcon(emoji: row.category.displayIcon, size: 32)
                    .opacity(row.isIncluded ? 1 : 0.4)
                Text(row.category.name)
                    .font(.appSubheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(row.isIncluded ? Color.primary : Color.secondary)
                Spacer(minLength: 8)
                TextField("0", text: Binding(
                    get: { row.amountText },
                    set: { viewModel.setAmountText($0, for: row) }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .disabled(!row.isIncluded)
                .accessibilityLabel("Budget amount for \(row.category.name)")
                Toggle("", isOn: Binding(
                    get: { row.isIncluded },
                    set: { viewModel.setIncluded(row, included: $0) }
                ))
                .labelsHidden()
                .accessibilityLabel("Include \(row.category.name) in the plan")
            }
            if row.isIncluded {
                Text(row.rationale)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func savingsRow(_ viewModel: BudgetSuggestionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BloomRowIcon(emoji: "💰", size: 32)
                    .opacity(viewModel.savingsIncluded ? 1 : 0.4)
                Text("Savings")
                    .font(.appSubheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(viewModel.savingsIncluded ? Color.primary : Color.secondary)
                Spacer(minLength: 8)
                TextField("0", text: Binding(
                    get: { viewModel.savingsAmountText },
                    set: { viewModel.savingsAmountText = $0 }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .disabled(!viewModel.savingsIncluded)
                .accessibilityLabel("Monthly savings amount")
                Toggle("", isOn: Binding(
                    get: { viewModel.savingsIncluded },
                    set: { viewModel.savingsIncluded = $0 }
                ))
                .labelsHidden()
                .accessibilityLabel("Include savings in the plan")
            }
            if viewModel.savingsIncluded, !viewModel.savingsRationale.isEmpty {
                Text(viewModel.savingsRationale)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func apiKeySheet(_ viewModel: BudgetSuggestionViewModel) -> some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("AIza…", text: Binding(
                        get: { viewModel.apiKeyText },
                        set: { viewModel.apiKeyText = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("Google Gemini API Key")
                } footer: {
                    Text("Free with a Google account — no credit card. Stored in the iOS Keychain only, and used solely to tailor budget suggestions: your category totals and recent transactions (date, amount, category, merchant) are sent — never account names, balances, or notes. Get a key at aistudio.google.com/apikey.")
                }
                if viewModel.hasAPIKey {
                    Section {
                        Button("Remove Key", role: .destructive) {
                            GeminiService.setAPIKey(nil)
                            isEditingKey = false
                        }
                    }
                }
            }
            .navigationTitle("AI Suggestions")
            .accentWash(.budgets)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingKey = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveAPIKey()
                        isEditingKey = false
                    }
                    .disabled(viewModel.apiKeyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    BudgetSuggestionView(month: .now)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
