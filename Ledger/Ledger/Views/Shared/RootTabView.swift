import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection = 0
    @State private var tabSwipe = TabSwipeCoordinator()

    var body: some View {
        // A paged TabView so the screens can be swiped between left/right. The native tab bar
        // doesn't support swiping, so we hide its page indicator and supply our own bar below.
        TabView(selection: $selection) {
            DashboardView().tag(0)
            AccountListView().tag(1)
            TransactionListView().tag(2)
            BudgetListView().tag(3)
            MoreView().tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // While a screen is pushed inside any tab, the paging swipe is disabled so a horizontal
        // swipe pops back to the previous screen instead of dragging to the next tab.
        .scrollDisabled(!tabSwipe.isTabSwipeEnabled)
        .environment(tabSwipe)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $selection)
        }
    }
}

private struct CustomTabBar: View {
    @Binding var selection: Int

    private let items: [(title: String, icon: String)] = [
        ("Dashboard", "house.fill"),
        ("Accounts", "banknote.fill"),
        ("Transactions", "list.bullet"),
        ("Budgets", "chart.pie.fill"),
        ("More", "ellipsis.circle.fill"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = index }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
                        Text(item.title)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == index ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == index ? [.isSelected] : [])
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
                        InsightsView().disablesTabSwipe()
                    } label: {
                        Label("Insights", systemImage: "sparkles")
                    }
                    NavigationLink {
                        ReportsView().disablesTabSwipe()
                    } label: {
                        Label("Reports", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        RecurringView().disablesTabSwipe()
                    } label: {
                        Label("Recurring", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section("Planning") {
                    NavigationLink {
                        SavingsGoalsView().disablesTabSwipe()
                    } label: {
                        Label("Savings Goals", systemImage: "target")
                    }
                    NavigationLink {
                        DebtListView().disablesTabSwipe()
                    } label: {
                        Label("Debt Tracker", systemImage: "creditcard.trianglebadge.exclamationmark")
                    }
                    NavigationLink {
                        BillRemindersView().disablesTabSwipe()
                    } label: {
                        Label("Bill Reminders", systemImage: "bell.badge")
                    }
                }
                Section("Organize") {
                    NavigationLink {
                        CategoryEditorView().disablesTabSwipe()
                    } label: {
                        Label("Categories", systemImage: "tag.fill")
                    }
                }
                Section("Data Sources") {
                    NavigationLink {
                        IntegrationsSettingsView().disablesTabSwipe()
                    } label: {
                        Label("Connect Wealthsimple", systemImage: "link")
                    }
                    NavigationLink {
                        CSVImportView().disablesTabSwipe()
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
