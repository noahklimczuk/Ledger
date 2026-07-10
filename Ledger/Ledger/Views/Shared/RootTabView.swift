import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        // A paged TabView keeps the left/right swipe between the five root screens. We no longer
        // put `scrollDisabled` on it: that modifier propagates through the environment and was
        // disabling the *inner* Lists/ScrollViews (so pushed screens couldn't scroll at all).
        // The floating Liquid Glass bar below is our own; the native page indicator stays hidden.
        TabView(selection: $selection) {
            DashboardView().tag(0)
            AccountListView().tag(1)
            TransactionListView().tag(2)
            BudgetListView().tag(3)
            MoreView().tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
    }
}

/// A floating, pill-shaped tab bar rendered in Liquid Glass on iOS 26+ (with a material fallback
/// on earlier releases). Sits inset from the screen edges so content scrolls behind/under it.
private struct FloatingTabBar: View {
    @Binding var selection: Int

    private let items: [(title: String, icon: String)] = [
        ("Dashboard", "house.fill"),
        ("Accounts", "banknote.fill"),
        ("Transactions", "list.bullet"),
        ("Budgets", "chart.pie.fill"),
        ("More", "ellipsis.circle.fill"),
    ]

    var body: some View {
        bar
            .padding(.horizontal, 16)
            .padding(.top, 6)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 0) {
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
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }

    /// The pill background: real Liquid Glass where available, a material capsule otherwise.
    @ViewBuilder
    private var bar: some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
