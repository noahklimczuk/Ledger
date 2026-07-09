import SwiftUI

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
