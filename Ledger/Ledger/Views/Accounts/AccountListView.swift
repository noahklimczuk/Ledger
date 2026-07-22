import SwiftUI
import SwiftData

/// The Bloom Accounts screen. A pushed view from Home that groups accounts by type:
/// net worth hero at the top, cash & savings, then debt, and a one-tap Wealthsimple connect row.
struct AccountListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AccountsViewModel?
    @State private var isPresentingNewAccount = false
    @State private var editingAccount: Account?
    @State private var isPresentingWealthsimple = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if let viewModel {
                    netWorthCard(viewModel)
                    cashAndSavingsSection(viewModel)
                    debtSection(viewModel)
                    connectButton
                } else {
                    LoadingView()
                }
            }
            .padding()
        }
        .accentWash(.accounts)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .accent(.accounts)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNewAccount = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Account")
            }
        }
        .sheet(isPresented: $isPresentingNewAccount, onDismiss: { viewModel?.load() }) {
            AccountEditView(account: nil, viewModel: viewModel)
        }
        .sheet(item: $editingAccount, onDismiss: { viewModel?.load() }) { account in
            AccountEditView(account: account, viewModel: viewModel)
        }
        .sheet(isPresented: $isPresentingWealthsimple) {
            NavigationStack { IntegrationsSettingsView() }
        }
        .task {
            if viewModel == nil { viewModel = AccountsViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
        .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
    }

    // MARK: - Net worth

    private func netWorthCard(_ viewModel: AccountsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Net worth".uppercased())
                .font(.appCaption2.weight(.heavy))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            CountingCurrency(value: viewModel.netWorth)
                .font(.appDisplay)
                .foregroundStyle(Color.primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: viewModel.netWorthDeltaThisMonth >= 0 ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.heavy))
                Text(CurrencyFormatter.string(from: viewModel.netWorthDeltaThisMonth))
                    .font(.appCaption.weight(.heavy))
            }
            .foregroundStyle(viewModel.netWorthDeltaThisMonth >= 0 ? Palette.income : Palette.expense)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background((viewModel.netWorthDeltaThisMonth >= 0 ? Palette.income : Palette.expense).opacity(0.12), in: Capsule())

            if let synced = viewModel.lastSyncedAt {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Palette.income)
                        .frame(width: 8, height: 8)
                    Text("All synced · \(synced.formatted(.relative(presentation: .named)))")
                        .font(.appCaption.weight(.bold))
                        .foregroundStyle(Palette.greenDeep)
                }
                .padding(.top, 4)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Palette.green.opacity(0.10), Color.appSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.appSurface.opacity(0.70))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .shadow(color: Color.bloomShadow, radius: 18, y: 11)
        .shadow(color: Color.bloomHighlight, radius: 12, x: -7, y: -7)
    }

    // MARK: - Sections

    private func cashAndSavingsSection(_ viewModel: AccountsViewModel) -> some View {
        let cashAccounts = viewModel.accounts.filter { !$0.type.isLiability }
        return groupCard(title: "Cash & savings", accounts: cashAccounts, viewModel: viewModel)
    }

    private func debtSection(_ viewModel: AccountsViewModel) -> some View {
        let debts = viewModel.accounts.filter { $0.type.isLiability }
        return groupCard(title: "Debt", accounts: debts, viewModel: viewModel)
    }

    private func groupCard(title: String, accounts: [Account], viewModel: AccountsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.appHeadline.weight(.heavy))
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)

            if accounts.isEmpty {
                Text("None yet")
                    .font(.appSubheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts, id: \.persistentModelID) { account in
                        Button { editingAccount = account } label: {
                            AccountRow(account: account)
                        }
                        .buttonStyle(.pressable)
                        if account.persistentModelID != accounts.last?.persistentModelID {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    // MARK: - Connect

    private var connectButton: some View {
        Button { isPresentingWealthsimple = true } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "link", accent: .accounts, size: 38, filled: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect another institution")
                        .font(.appBodyMedium.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("Wealthsimple Cash · free, no aggregator")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.pressable)
        .card()
    }
}

private struct AccountRow: View {
    let account: Account

    private var accent: Accent {
        switch account.type {
        case .chequing: .accounts
        case .savings: .goals
        case .credit: .debt
        case .investment: .insights
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            accountIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.appBodyMedium.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(CurrencyFormatter.string(from: account.currentBalance, currencyCode: account.currencyCode))
                .font(.appBody.weight(.heavy))
                .foregroundStyle(account.currentBalance < 0 ? Palette.expense : Color.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }

    private var accountIcon: some View {
        Group {
            if account.isLinked {
                IconBadge(systemName: account.type.sfSymbolName, accent: accent, size: 42)
            } else {
                IconBadge(systemName: account.type.sfSymbolName, accent: accent, size: 42, filled: false)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let institution = account.institutionName, !institution.isEmpty {
            parts.append(institution)
        } else {
            parts.append(account.type.displayName)
        }
        if account.isLinked {
            parts.append("linked")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        AccountListView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
    .environment(AppRefreshCoordinator())
}
