import SwiftUI
import SwiftData

/// Bloom new / edit transaction sheet. The layout mirrors the rendering: a large hero amount with a
/// custom number pad, expense / income toggle, horizontal category chips, account & date cards,
/// merchant, notes, and split/debt options.
struct TransactionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction?
    @State private var viewModel: TransactionEditViewModel?

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var debts: [Debt] = []
    @State private var isPresentingDatePicker = false
    @FocusState private var merchantFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ScrollView {
                        VStack(spacing: Theme.sectionSpacing) {
                            amountHero(viewModel)
                            merchantField(viewModel)
                            categoryChips(viewModel)
                            accountDateCards(viewModel)
                            splitsSection(viewModel)
                            notesSection(viewModel)
                            saveButton(viewModel)
                        }
                        .padding()
                    }
                    .background(Color.appBackground.ignoresSafeArea())
                } else {
                    LoadingView()
                }
            }
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .accent(.transactions)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingDatePicker) {
                NavigationStack {
                    DatePickerSheet(date: Binding(
                        get: { viewModel?.date ?? .now },
                        set: { viewModel?.date = $0 }
                    ))
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = TransactionEditViewModel(modelContext: modelContext, transaction: transaction)
            }
            accounts = (try? modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))) ?? []
            categories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))) ?? []
            let activeDebts = (try? modelContext.fetch(FetchDescriptor<Debt>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.name)]))) ?? []
            if let current = viewModel?.debt, !activeDebts.contains(where: { $0.persistentModelID == current.persistentModelID }) {
                debts = activeDebts + [current]
            } else {
                debts = activeDebts
            }
            if viewModel?.account == nil, accounts.count == 1 {
                viewModel?.account = accounts.first
            }
        }
    }

    // MARK: - Hero

    private func amountHero(_ viewModel: TransactionEditViewModel) -> some View {
        VStack(spacing: 18) {
            Picker("Type", selection: Binding(
                get: { viewModel.direction },
                set: { viewModel.direction = $0 }
            )) {
                ForEach(TransactionEditViewModel.Direction.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Text(displayAmount(for: viewModel))
                .font(.appMoney)
                .foregroundStyle(viewModel.direction == .expense ? Color.primary : Palette.income)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 24)

            BloomKeypad(value: Binding(
                get: { viewModel.amountText },
                set: { viewModel.amountText = $0 }
            ))
                .padding(.horizontal, 10)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Palette.green.opacity(0.12), Color.appSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.appSurface.opacity(0.60))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .shadow(color: Color.bloomShadow, radius: 18, y: 11)
        .shadow(color: Color.bloomHighlight, radius: 12, x: -7, y: -7)
    }

    private func displayAmount(for viewModel: TransactionEditViewModel) -> String {
        let magnitude = abs(ImportValueParsing.decimal(from: viewModel.amountText) ?? 0)
        let sign = viewModel.direction == .expense ? "−" : "+"
        return "\(sign) \(CurrencyFormatter.string(from: magnitude))"
    }

    // MARK: - Merchant

    private func merchantField(_ viewModel: TransactionEditViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merchant")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            TextField("Starbucks, Paycheque, Rent…", text: Binding(
                get: { viewModel.merchant },
                set: { viewModel.merchant = $0 }
            ))
            .font(.appHeadline.weight(.semibold))
            .focused($merchantFocused)
            .padding(14)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Categories

    private func categoryChips(_ viewModel: TransactionEditViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    CategoryChip(
                        name: "Uncategorized",
                        systemImage: "questionmark.circle.fill",
                        color: .gray,
                        isSelected: viewModel.category == nil
                    ) {
                        viewModel.category = nil
                    }

                    ForEach(categories, id: \.persistentModelID) { category in
                        CategoryChip(
                            name: category.name,
                            systemImage: category.sfSymbolName,
                            color: Color(hex: category.colorHex),
                            isSelected: viewModel.category?.persistentModelID == category.persistentModelID
                        ) {
                            viewModel.category = category
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Account / Date

    private func accountDateCards(_ viewModel: TransactionEditViewModel) -> some View {
        HStack(spacing: Theme.sectionSpacing) {
            Menu {
                Picker("Account", selection: Binding(
                    get: { viewModel.account },
                    set: { viewModel.account = $0 }
                )) {
                    Text("Select an account").tag(Account?.none)
                    ForEach(accounts, id: \.persistentModelID) { account in
                        Text(account.name).tag(account as Account?)
                    }
                }
            } label: {
                ValueCard(
                    title: "Account",
                    value: viewModel.account?.name ?? "Select",
                    icon: viewModel.account?.type.sfSymbolName ?? "banknote",
                    accent: .accounts
                )
            }
            .buttonStyle(.plain)

            Button { isPresentingDatePicker = true } label: {
                ValueCard(
                    title: "Date",
                    value: DateFormatting.medium(viewModel.date),
                    icon: "calendar",
                    accent: .transactions
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Splits / Debt

    private func splitsSection(_ viewModel: TransactionEditViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("Split")
            SplitEditorView(viewModel: viewModel, categories: categories)
                .padding(Theme.cardPadding)
                .card()

            if !debts.isEmpty {
                Menu {
                    Picker("Debt", selection: Binding(
                        get: { viewModel.debt },
                        set: { viewModel.debt = $0 }
                    )) {
                        Text("None").tag(Debt?.none)
                        ForEach(debts, id: \.persistentModelID) { debt in
                            Label(debt.name, systemImage: debt.kind.sfSymbolName).tag(debt as Debt?)
                        }
                    }
                } label: {
                    ValueCard(
                        title: "Debt",
                        value: viewModel.debt?.name ?? "None",
                        icon: "creditcard",
                        accent: .debt
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Notes / Save

    private func notesSection(_ viewModel: TransactionEditViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { viewModel.notes },
                set: { viewModel.notes = $0 }
            ))
            .font(.appBody)
            .frame(minHeight: 80)
            .padding(12)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
        }
        .padding(Theme.cardPadding)
        .card()
    }

    private func saveButton(_ viewModel: TransactionEditViewModel) -> some View {
        Button {
            viewModel.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } label: {
            Label("Save", systemImage: "checkmark")
                .font(.appSubheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.canSave != true)
    }
}

// MARK: - Supporting views

private struct CategoryChip: View {
    let name: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isSelected ? 8 : 6) {
                Image(systemName: systemImage)
                    .font(.system(size: isSelected ? 24 : 20, weight: .bold))
                    .symbolEffect(.bounce, value: isSelected)
                    .foregroundStyle(isSelected ? .white : color)
                Text(name)
                    .font(isSelected ? .appCallout.weight(.heavy) : .appCaption.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Color.primary)
            }
            .padding(.horizontal, isSelected ? 22 : 16)
            .padding(.vertical, isSelected ? 14 : 10)
            .background(isSelected ? color.opacity(0.92) : Color.appSurface, in: Capsule())
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.appHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }
}

private struct ValueCard: View {
    let title: String
    let value: String
    let icon: String
    let accent: Accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IconBadge(systemName: icon, accent: accent, size: 32, filled: false)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appCaption2.weight(.heavy))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.appBodyMedium.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .shadow(color: Color.bloomShadow, radius: 10, y: 5)
        .shadow(color: Color.bloomHighlight, radius: 8, x: -4, y: -4)
    }
}

private struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()

            Button("Done") { dismiss() }
                .font(.appSubheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Select Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

#Preview {
    TransactionEditView(transaction: nil)
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
