import SwiftUI
import SwiftData

/// Reviewable AI budget proposal for one month. Everything is a *proposal* until the user taps
/// Apply: amounts are editable, categories can be excluded, and cancelling changes nothing.
/// The statistics come from on-device aggregation; the optional Anthropic refinement only ever
/// receives category totals (see `AnthropicService`).
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
            ContentUnavailableView {
                Label("Budget Applied", systemImage: "checkmark.circle.fill")
            } description: {
                Text("\(viewModel.appliedCount) budget\(viewModel.appliedCount == 1 ? "" : "s") set for \(DateFormatting.monthYear(viewModel.month)).")
            } actions: {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
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
            } footer: {
                Text("Toggle a category off to leave its budget unchanged. Amounts are editable. Nothing is saved until you tap Apply.")
            }

            if let aiStatus = viewModel.aiStatus {
                Section {
                    Button {
                        isEditingKey = true
                    } label: {
                        Label(aiStatus, systemImage: viewModel.hasAPIKey ? "exclamationmark.triangle" : "sparkles")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Pieces

    private func summaryCard(_ viewModel: BudgetSuggestionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient.brand)
                Text("Plan for \(DateFormatting.monthYear(viewModel.month))")
                    .font(.headline)
                Spacer()
                if viewModel.isRefining {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Getting AI suggestions")
                }
            }
            Text(viewModel.planSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                statTile("Proposed total", value: CurrencyFormatter.string(from: viewModel.totalProposed))
                statTile("Avg. income", value: CurrencyFormatter.string(from: viewModel.averageMonthlyIncome))
                statTile("History", value: "\(viewModel.monthsAnalyzed) mo")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 4)
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proposalRow(_ row: BudgetSuggestionViewModel.ProposalRow, viewModel: BudgetSuggestionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: row.category.sfSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: row.category.colorHex), in: Circle())
                    .opacity(row.isIncluded ? 1 : 0.4)
                Text(row.category.name)
                    .font(.subheadline.weight(.medium))
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
                    .font(.caption)
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
                    SecureField("sk-ant-…", text: Binding(
                        get: { viewModel.apiKeyText },
                        set: { viewModel.apiKeyText = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored in the iOS Keychain only. Used solely to tailor budget suggestions — only aggregated category totals are sent, never your transactions or account details. Get a key at console.anthropic.com.")
                }
                if viewModel.hasAPIKey {
                    Section {
                        Button("Remove Key", role: .destructive) {
                            AnthropicService.setAPIKey(nil)
                            isEditingKey = false
                        }
                    }
                }
            }
            .navigationTitle("AI Suggestions")
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
