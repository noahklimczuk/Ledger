import SwiftUI
import SwiftData

/// The app's root: a native `TabView` over the five primary screens. On iOS 26 this renders as the
/// system Liquid Glass tab bar — a floating, translucent pill that content scrolls underneath —
/// identical to the App Store's, because it *is* the system bar. Each tab supplies its own
/// `NavigationStack`, so large titles and back stacks stay per-tab.
///
/// This replaces an earlier hand-built floating bar layered over a horizontal `ScrollView` pager.
/// That existed to keep a swipe-between-tabs gesture the paged `TabView` (`.tabViewStyle(.page)`, a
/// `UIPageViewController`) couldn't provide without crashing on overlapping large-title nav bars —
/// but the swipe was later disabled anyway, so the custom bar was fighting the system for nothing and
/// still couldn't match the real glass bar (it drew a flat pill and reserved a strip instead of
/// letting content pass under the glass). A *default* `TabView` uses `UITabBarController`, showing one
/// tab at a time, so it never hits that nav-controller-nesting crash. The selected tab tints with the
/// app's accent via the `.tint(.accentColor)` set on the scene in `LedgerApp`.
struct RootTabView: View {
    /// The selected tab index, bound so a horizontal swipe (below) can step between screens in
    /// addition to tapping the bar.
    @State private var selection = 0
    private static let tabCount = 5

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "house.fill", value: 0) {
                DashboardView().toolbar(.hidden, for: .tabBar)
            }
            Tab("Accounts", systemImage: "banknote.fill", value: 1) {
                AccountListView().toolbar(.hidden, for: .tabBar)
            }
            Tab("Transactions", systemImage: "list.bullet", value: 2) {
                TransactionListView().toolbar(.hidden, for: .tabBar)
            }
            Tab("Budgets", systemImage: "chart.pie.fill", value: 3) {
                BudgetListView().toolbar(.hidden, for: .tabBar)
            }
            Tab("More", systemImage: "ellipsis.circle.fill", value: 4) {
                MoreView().toolbar(.hidden, for: .tabBar)
            }
        }
        // Hide the system tab bar so only the custom floating pill shows. The modifier must sit on
        // *each tab's content* — applying it at the `TabView` level doesn't take on iOS 26, which left
        // the native bar visible *behind* the custom pill (the double-bar bug). The custom bar is
        // floated higher via `safeAreaInset`, which also reserves its space so scrolling content
        // clears it. The native `TabView` still owns tab switching and per-tab state, so none of the
        // old custom-pager bugs (zero-height pages, launch hang) can recur; only the bar is custom.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
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

/// A floating, pill-shaped tab bar raised off the bottom edge. It only draws the bar and writes the
/// selection binding — the enclosing `TabView` still manages the screens — so it carries none of the
/// custom-pager risk.
///
/// The redesign gives it the app's playful, multi-accent character: the selected tab expands into a
/// label pill filled with that section's signature gradient, the pill springs between tabs with a
/// `matchedGeometryEffect`, the icon does a symbol bounce as it's chosen, and the whole bar casts a
/// soft shadow in the current section's color — so the shell itself announces which area you're in.
private struct FloatingTabBar: View {
    @Binding var selection: Int
    /// Ties the moving selection pill to one identity so it springs between tabs.
    @Namespace private var pill

    private let items: [(title: String, icon: String, accent: Accent)] = [
        ("Dashboard", "house.fill", .dashboard),
        ("Accounts", "banknote.fill", .accounts),
        ("Transactions", "list.bullet", .transactions),
        ("Budgets", "chart.pie.fill", .budgets),
        ("More", "square.grid.2x2.fill", .insights),
    ]

    private var selectedAccent: Accent { items[selection].accent }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                tabButton(index)
            }
        }
        .padding(7)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(Capsule(style: .continuous).strokeBorder(Color.appHairline, lineWidth: 1))
        )
        .shadow(color: selectedAccent.base.opacity(0.30), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
        .animation(Motion.bouncy, value: selection)
    }

    /// One tab: a plain glyph that grows a gradient label pill in its section color when selected.
    private func tabButton(_ index: Int) -> some View {
        let item = items[index]
        let isSelected = selection == index
        return Button {
            Haptics.tap(.soft)
            selection = index
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 20, weight: .bold))
                    .symbolEffect(.bounce, value: isSelected)
                if isSelected {
                    Text(item.title)
                        .font(.system(size: 14, weight: .heavy))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary))
            .padding(.horizontal, isSelected ? 18 : 15)
            .padding(.vertical, 14)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(item.accent.gradient)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct MoreView: View {
    @State private var isPresentingCheckIn = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { isPresentingCheckIn = true } label: {
                        moreRow("Daily Check-In", "checklist", .checkIn)
                    }
                    .buttonStyle(.plain)
                } header: { sectionLabel("Routine") }

                Section {
                    moreLink("Financial Wellness", "leaf.fill", .wellness) { FinancialWellnessView() }
                    moreLink("Ask Ledger", "sparkles", .insights) { AskLedgerView() }
                    moreLink("Insights", "lightbulb.fill", .insights) { InsightsView() }
                    moreLink("Reports", "chart.bar.xaxis", .reports) { ReportsView() }
                    moreLink("Recurring", "arrow.triangle.2.circlepath", .recurring) { RecurringView() }
                } header: { sectionLabel("Insights") }

                Section {
                    moreLink("Savings Goals", "target", .goals) { SavingsGoalsView() }
                    moreLink("Debt Tracker", "creditcard.trianglebadge.exclamationmark", .debt) { DebtListView() }
                    moreLink("Bill Reminders", "bell.badge", .bills) { BillRemindersView() }
                } header: { sectionLabel("Planning") }

                Section {
                    moreLink("Categories", "tag.fill", .categories) { CategoryEditorView() }
                } header: { sectionLabel("Organize") }

                Section {
                    moreLink("Connect Wealthsimple", "link", .accounts) { IntegrationsSettingsView() }
                    moreLink("Import CSV / OFX", "square.and.arrow.down", .transactions) { CSVImportView() }
                } header: { sectionLabel("Data Sources") }
            }
            .navigationTitle("More")
            .sheet(isPresented: $isPresentingCheckIn) {
                DailyCheckInView()
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.appCaption.weight(.bold)).textCase(nil).foregroundStyle(.secondary)
    }

    private func moreLink<Destination: View>(
        _ title: String,
        _ icon: String,
        _ accent: Accent,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        let target = destination()
        return NavigationLink {
            target
        } label: {
            moreRow(title, icon, accent)
        }
    }

    private func moreRow(_ title: String, _ icon: String, _ accent: Accent) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, accent: accent, size: 34)
            Text(title).font(.appBodyMedium)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
