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
                            BloomKeypad(value: Binding(
                                get: { viewModel.amountText },
                                set: { viewModel.amountText = $0 }
                            ))
                        }
                        .padding()
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle(transaction == nil ? "New transaction" : "Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
            .accent(.transactions)
            .accentWash(.transactions)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.appCaption.weight(.black))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.appSurface, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.appHairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let viewModel, viewModel.canSave {
                            viewModel.save()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    } label: {
                        Text("Save")
                            .font(.appCaption.weight(.black))
                            .foregroundStyle(viewModel?.canSave == true ? AnyShapeStyle(Palette.greenDeep) : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                viewModel?.canSave == true ? AnyShapeStyle(Color.appSurface) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.appHairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel?.canSave != true)
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
        VStack(spacing: 14) {
            amountHeroText(for: viewModel)
                .padding(.horizontal, 24)

            directionPicker(viewModel)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func directionPicker(_ viewModel: TransactionEditViewModel) -> some View {
        HStack(spacing: 4) {
            directionButton(
                viewModel,
                .expense,
                accent: Accent(base: Palette.expense, deep: Palette.coralDeep)
            )
            directionButton(
                viewModel,
                .income,
                accent: Accent(base: Palette.income, deep: Palette.emeraldDeep)
            )
        }
        .padding(4)
        .background(Color.appSurface.opacity(0.8), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
    }

    private func directionButton(
        _ viewModel: TransactionEditViewModel,
        _ direction: TransactionEditViewModel.Direction,
        accent: Accent
    ) -> some View {
        let isSelected = viewModel.direction == direction
        return Button { viewModel.direction = direction } label: {
            Text(direction.label)
                .font(.appCaption.weight(.black))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.secondary))
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.clear),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.direction)
    }

    private func displayAmount(for viewModel: TransactionEditViewModel) -> String {
        let magnitude = abs(ImportValueParsing.decimal(from: viewModel.amountText) ?? 0)
        return CurrencyFormatter.string(from: magnitude)
    }

    private func amountHeroText(for viewModel: TransactionEditViewModel) -> some View {
        let raw = displayAmount(for: viewModel)
        let symbol = String(raw.prefix(1))
        let digits = String(raw.dropFirst())

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(symbol)
                .font(AppFont.scaled(32, relativeTo: .largeTitle, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.6))
                .baselineOffset(10)
            Text(digits)
                .font(.appDisplay)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
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
                        emoji: "❓",
                        isSelected: viewModel.category == nil
                    ) {
                        viewModel.category = nil
                    }

                    ForEach(categories, id: \.persistentModelID) { category in
                        CategoryChip(
                            name: category.name,
                            emoji: category.displayIcon,
                            isSelected: viewModel.category?.persistentModelID == category.persistentModelID
                        ) {
                            viewModel.category = category
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
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
                    icon: viewModel.account?.displayIcon ?? "🏦",
                    isEmoji: true,
                    accent: .accounts
                )
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

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
                .menuIndicator(.hidden)
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

}

// MARK: - Supporting views

private struct CategoryChip: View {
    let name: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isSelected ? 10 : 7) {
                Text(emoji)
                    .font(.system(size: isSelected ? 26 : 22))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .foregroundStyle(isSelected ? .white : Color.primary)
                Text(name)
                    .font(isSelected ? .appBody.weight(.heavy) : .appSubheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, isSelected ? 26 : 18)
            .padding(.vertical, isSelected ? 16 : 12)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [Palette.green, Palette.greenDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.appSurface),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.appHairline, lineWidth: 1)
            )
            .shadow(color: Color.bloomShadow, radius: 4, x: 2, y: 3)
            .shadow(color: Color.bloomHighlight, radius: 3, x: -1, y: -1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }
}

private struct ValueCard: View {
    let title: String
    let value: String
    let icon: String
    var isEmoji: Bool = false
    let accent: Accent

    private var iconView: some View {
        Group {
            if isEmoji {
                Text(icon)
                    .font(.system(size: 14))
            } else {
                Image(systemName: icon)
                    .font(AppFont.scaled(14, relativeTo: .subheadline, weight: .bold))
            }
        }
        .foregroundStyle(accent.base)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appCaption2.weight(.heavy))
                .tracking(0.3)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                iconView
                Text(value)
                    .font(.appBodyMedium.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .shadow(color: Color.bloomShadow, radius: 6, y: 3)
        .shadow(color: Color.bloomHighlight, radius: 5, x: -2, y: -3)
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
        .accentWash(.transactions)
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
