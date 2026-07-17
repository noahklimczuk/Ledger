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
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "house.fill") {
                DashboardView()
            }
            Tab("Accounts", systemImage: "banknote.fill") {
                AccountListView()
            }
            Tab("Transactions", systemImage: "list.bullet") {
                TransactionListView()
            }
            Tab("Budgets", systemImage: "chart.pie.fill") {
                BudgetListView()
            }
            Tab("More", systemImage: "ellipsis.circle.fill") {
                MoreView()
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
