import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }

            AccountListView()
                .tabItem { Label("Accounts", systemImage: "banknote.fill") }

            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }

            BudgetListView()
                .tabItem { Label("Budgets", systemImage: "chart.pie.fill") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}

private struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
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
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
}
