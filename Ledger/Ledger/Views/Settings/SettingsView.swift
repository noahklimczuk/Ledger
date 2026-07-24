import SwiftUI
import SwiftData

/// Settings, account, and data-management screen reachable from the Home gradient avatar.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ledgerColorScheme") private var colorSchemeRaw = AppColorScheme.system.rawValue
    @State private var isPresentingExportShare = false
    @State private var isConfirmingReset = false
    @State private var resetMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    profileCard
                    appearanceCard
                    dataCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .accent(.dashboard)
            .accentWash(.dashboard)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.appSubheadline.weight(.semibold))
                }
            }
            .sheet(isPresented: $isPresentingExportShare) {
                if let exportURL {
                    ShareSheet(activityItems: [exportURL])
                }
            }
            .alert("Reset Data", isPresented: $isConfirmingReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { resetAllData() }
            } message: {
                Text("This will permanently delete all accounts, transactions, budgets, goals, and bills. This cannot be undone.")
            }
            .alert("Reset complete", isPresented: Binding(get: { resetMessage != nil }, set: { if !$0 { resetMessage = nil } })) {
                Button("OK", role: .cancel) { resetMessage = nil }
            } message: {
                Text(resetMessage ?? "")
            }
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.peach, Palette.peri],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Text("🌿")
                        .font(.system(size: 28))
                )
                .shadow(color: Color.bloomShadow, radius: 10, x: 4, y: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ledger for Noah")
                    .font(.appHeadline.weight(.heavy))
                    .foregroundStyle(Color.primary)
                Text("Built for one account, blooming.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.appCaption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Button { colorSchemeRaw = scheme.rawValue } label: {
                        HStack(spacing: 6) {
                            Text(appearanceIcon(scheme))
                                .font(.system(size: 14))
                            Text(scheme.displayName)
                                .font(.appCaption2.weight(.heavy))
                        }
                        .foregroundStyle(colorSchemeRaw == scheme.rawValue ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            colorSchemeRaw == scheme.rawValue
                                ? AnyShapeStyle(Accent.dashboard.base)
                                : AnyShapeStyle(Color.appSurface2),
                            in: Capsule(style: .continuous)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(colorSchemeRaw == scheme.rawValue ? Color.clear : Color.appHairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .card()
    }

    private func appearanceIcon(_ scheme: AppColorScheme) -> String {
        switch scheme {
        case .system: return "🌗"
        case .light: return "☀️"
        case .dark: return "🌙"
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data")
                .font(.appCaption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                settingsButton(title: "Export transactions", icon: "📤") {
                    exportTransactions()
                }
                SettingsDivider()
                settingsButton(title: "Reset all data", icon: "🗑️") {
                    isConfirmingReset = true
                }
            }
        }
        .card()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.appCaption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ledger")
                    .font(.appHeadline.weight(.heavy))
                Text("A private, on-device money companion for Noah.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                Text("Version \(appVersion())")
                    .font(.appCaption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .card()
    }

    private func settingsButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                BloomRowIcon(emoji: icon, size: 40)
                Text(title)
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("›")
                    .font(.appCaption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func exportTransactions() {
        let all = (try? modelContext.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var lines = ["Date,Merchant,Amount,Category,Account,Notes"]
        for tx in all {
            let date = DateFormatting.short(tx.date)
            let merchant = csvField(tx.merchant)
            let amount = CurrencyFormatter.string(from: tx.amount)
            let category = tx.category?.name ?? "Uncategorized"
            let account = tx.account?.name ?? ""
            let notes = csvField(tx.notes ?? "")
            lines.append("\(date),\(merchant),\(amount),\(category),\(account),\(notes)")
        }
        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-export.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            isPresentingExportShare = true
        } catch {
            resetMessage = "Could not create export file."
        }
    }

    private func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func resetAllData() {
        deleteAll(Account.self)
        deleteAll(Transaction.self)
        deleteAll(SplitAllocation.self)
        deleteAll(Category.self)
        deleteAll(Budget.self)
        deleteAll(BudgetPeriod.self)
        deleteAll(Tag.self)
        deleteAll(CategorizationRule.self)
        deleteAll(DebtRule.self)
        deleteAll(RecurringSeries.self)
        deleteAll(SavingsGoal.self)
        deleteAll(BillReminder.self)
        deleteAll(InsightState.self)
        deleteAll(Debt.self)
        deleteAll(AdvisorChat.self)
        deleteAll(AdvisorChatMessage.self)

        DefaultDataSeeder.resetSeed()
        try? modelContext.save()

        Task {
            await refresh.refresh(container: modelContext.container)
        }

        resetMessage = "All data has been reset. Categories will re-seed on the next refresh."
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let descriptor = FetchDescriptor<T>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        for item in items { modelContext.delete(item) }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.appHairline)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}
