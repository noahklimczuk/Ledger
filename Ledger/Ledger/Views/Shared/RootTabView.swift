import SwiftUI
import SwiftData
import Observation

/// The app's root: a native `TabView` over the five primary screens. The visual tab bar renders as
/// a floating Liquid Glass pill with Home in the centre: Wellness · Activity · Home · Budgets ·
/// More. Each tab supplies its own `NavigationStack`, so large titles and back stacks stay per-tab.
/// Accounts and Recurring live under Home (via the balance card) and More, matching the `bloom-ios`
/// rendering.
struct RootTabView: View {
    @Environment(AppLockService.self) private var lockService
    /// The selected tab index. Visual bar order is Wellness(0), Activity(1), Home(2), Budgets(3), More(4)
    /// so Home sits in the centre.
    @State private var selection = 2
    @State private var isPresentingAskLedger = false
    private static let tabCount = 5

    var body: some View {
        TabView(selection: $selection) {
            Tab("Wellness", systemImage: "leaf.fill", value: 0) {
                FinancialWellnessView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Activity", systemImage: "chart.bar.xaxis", value: 1) {
                TransactionListView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Home", systemImage: "house.fill", value: 2) {
                DashboardView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Budgets", systemImage: "chart.pie.fill", value: 3) {
                BudgetListView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("More", systemImage: "square.grid.2x2.fill", value: 4) {
                MoreView().toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .padding(.bottom, 1)
        // Hide the system tab bar so only the custom floating pill shows. The modifier must sit on
        // *each tab's content* — applying it at the `TabView` level doesn't take on iOS 26, which left
        // the native bar visible *behind* the custom pill (the double-bar bug). The custom bar is
        // floated higher via `safeAreaInset`, which also reserves its space so scrolling content
        // clears it. A 1-point bottom padding on `TabView` forces SwiftUI to break contact with the
        // bottom safe area, so the inset actually pushes scrollable content up.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
        .onChange(of: lockService.isUnlocked) { _, isUnlocked in
            if isUnlocked { selection = 2 }
        }
        .overlay(alignment: .bottomTrailing) {
            if selection != 2 {
                AskLedgerButton(isPresented: $isPresentingAskLedger)
                    .padding(.trailing, 12)
                    .padding(.bottom, 88)
            }
        }
        .sheet(isPresented: $isPresentingAskLedger) {
            AskLedgerView(month: .now)
        }
        .simultaneousGesture(swipeBetweenTabs)
    }

    /// A horizontal flick that steps to the adjacent tab, so the five screens can be swiped through as
    /// well as tapped — the native tab bar has no built-in page-swipe. Deliberately high thresholds (a
    /// long, clearly-horizontal drag) so it doesn't fire on a List row's shorter swipe-to-delete/
    /// -review or on a vertical scroll. Runs `.simultaneousGesture` so it coexists with those rather
    /// than stealing their touches.
    private var swipeBetweenTabs: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 90, abs(dx) > abs(dy) * 2 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    selection = max(0, min(Self.tabCount - 1, selection + (dx < 0 ? 1 : -1)))
                }
            }
    }
}

/// A true Liquid Glass floating tab bar with five equal-width tabs.
///
/// Modeled on the App Store tab bar: an extremely translucent frosted pill that lets the screen
/// behind it show through, with the Bloom top sheen, a soft bottom inner glow, and a hairline
/// edge. The selected tab gets a periwinkle wash, bold weight, and a filled SF Symbol. There is no
/// giant centre FAB — Home sits in the middle as a regular tab.
private struct FloatingTabBar: View {
    @Binding var selection: Int

    /// Visual order: Wellness · Activity · Home · Budgets · More. Home sits in the centre.
    private let items: [(title: String, icon: String, selected: String)] = [
        ("Wellness", "heart", "heart.fill"),
        ("Activity", "chart.bar", "chart.bar.fill"),
        ("Home", "house", "house.fill"),
        ("Budgets", "wallet.bifold", "wallet.bifold.fill"),
        ("More", "ellipsis", "ellipsis"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
                tabButton(index)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(glassBar)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(Motion.bouncy, value: selection)
    }

    private var glassBar: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
            Capsule(style: .continuous)
                .fill(Color.appSurface.opacity(0.06))
            // ::before top sheen (30% white -> transparent by 44%)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.32), location: 0),
                            .init(color: Color.white.opacity(0.06), location: 0.44),
                            .init(color: Color.clear, location: 0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
            // bottom inner highlight (inset 0 -8px 18px var(--sl))
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0),
                            .init(color: Color.white.opacity(0.04), location: 0.55),
                            .init(color: Color.white.opacity(0.10), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 14)
    }

    private func tabButton(_ index: Int) -> some View {
        let item = items[index]
        let isSelected = selection == index
        return Button {
            Haptics.tap(.soft)
            selection = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? item.selected : item.icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(item.title)
                    .font(AppFont.scaled(10, relativeTo: .caption2, weight: isSelected ? .bold : .semibold))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Accent.wellness.deep) : AnyShapeStyle(Color.primary.opacity(0.55)))
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    selectedPill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectedPill() -> some View {
        Capsule(style: .continuous)
            .fill(Accent.wellness.base.opacity(0.13))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}

private struct MoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @AppStorage("ledgerColorScheme") private var colorSchemeRaw = AppColorScheme.system.rawValue
    @State private var isPresentingCheckIn = false
    @State private var isPresentingCSVImport = false
    @State private var isPresentingExportShare = false
    @State private var exportURL: URL?
    @State private var isConfirmingReset = false
    @State private var resetMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    profileCard
                    appearanceCard
                    dataCard
                    aboutCard
                }
                .padding()
            }
            .navigationTitle("More")
            .accent(.dashboard)
            .accentWash(.dashboard)
            .sheet(isPresented: $isPresentingCheckIn) {
                DailyCheckInView()
            }
            .sheet(isPresented: $isPresentingCSVImport) {
                CSVImportView()
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
                                ? AnyShapeStyle(Accent.wellness.base)
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
                MoreButton(title: "Import CSV / OFX", icon: "📥") {
                    isPresentingCSVImport = true
                }
                MoreDivider()
                MoreButton(title: "Export transactions", icon: "📤") {
                    exportTransactions()
                }
                MoreDivider()
                MoreButton(title: "Reset all data", icon: "🗑️") {
                    isConfirmingReset = true
                }
            }
        }
        .card()
    }

    // MARK: - About

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

    private func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

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

private struct MoreRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            BloomRowIcon(emoji: icon, size: 40)
            Text(title)
                .font(.appSubheadline.weight(.semibold))
            Spacer()
            Text("›")
                .font(.appCaption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct MoreButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MoreRow(title: title, icon: icon)
        }
        .buttonStyle(.pressable)
    }
}

private struct MoreDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.appHairline)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

/// A compact, floating Ask Ledger dot. The "Ask Ledger" badge is pinned to the top-right corner of
/// the dot and offset so it overlaps the dot and extends into the screen corner. Hidden on Home
/// because the Dashboard already has its own Ask Ledger card.
private struct AskLedgerButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            Haptics.tap(.soft)
            isPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 50, height: 50)
                    .shadow(color: Accent.insights.base.opacity(0.35), radius: 10, x: 0, y: 5)
                Circle()
                    .fill(Accent.insights.gradient)
                    .frame(width: 46, height: 46)
                Text("✨")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .topTrailing) {
                Text("Ask Ledger")
                    .font(.appCaption2.weight(.heavy))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appSurface, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.appHairline, lineWidth: 1)
                    )
                    .shadow(color: Color.bloomShadow, radius: 6, x: 0, y: 3)
                    .offset(x: 6, y: -6)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Ask Ledger")
    }
}

/// A UIKit `UIActivityViewController` wrapper so the More screen can share the exported CSV.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RootTabView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
