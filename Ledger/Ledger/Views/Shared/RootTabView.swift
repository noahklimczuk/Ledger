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
                DashboardView()
            }
            Tab("Accounts", systemImage: "banknote.fill", value: 1) {
                AccountListView()
            }
            Tab("Transactions", systemImage: "list.bullet", value: 2) {
                TransactionListView()
            }
            Tab("Budgets", systemImage: "chart.pie.fill", value: 3) {
                BudgetListView()
            }
            Tab("More", systemImage: "ellipsis.circle.fill", value: 4) {
                MoreView()
            }
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

private struct MoreView: View {
    @State private var isPresentingCheckIn = false

    var body: some View {
        NavigationStack {
            List {
                Section("Routine") {
                    Button {
                        isPresentingCheckIn = true
                    } label: {
                        Label("Daily Check-In", systemImage: "checklist")
                    }
                }
                Section("Insights") {
                    NavigationLink {
                        InsightsView()
                    } label: {
                        Label("Insights", systemImage: "sparkles")
                    }
                    NavigationLink {
                        ReportsView()
                    } label: {
                        Label("Reports", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        RecurringView()
                    } label: {
                        Label("Recurring", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section("Planning") {
                    NavigationLink {
                        SavingsGoalsView()
                    } label: {
                        Label("Savings Goals", systemImage: "target")
                    }
                    NavigationLink {
                        DebtListView()
                    } label: {
                        Label("Debt Tracker", systemImage: "creditcard.trianglebadge.exclamationmark")
                    }
                    NavigationLink {
                        BillRemindersView()
                    } label: {
                        Label("Bill Reminders", systemImage: "bell.badge")
                    }
                }
                Section("Organize") {
                    NavigationLink {
                        CategoryEditorView()
                    } label: {
                        Label("Categories", systemImage: "tag.fill")
                    }
                }
                Section("Data Sources") {
                    NavigationLink {
                        IntegrationsSettingsView()
                    } label: {
                        Label("Connect Wealthsimple", systemImage: "link")
                    }
                    NavigationLink {
                        CSVImportView()
                    } label: {
                        Label("Import CSV / OFX", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("More")
            .sheet(isPresented: $isPresentingCheckIn) {
                DailyCheckInView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
