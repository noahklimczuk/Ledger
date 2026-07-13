import SwiftUI
import SwiftData

struct RootTabView: View {
    /// The single source of truth for the current tab: the page snapped under the horizontal pager.
    /// A swipe updates it directly; the floating bar reads and writes it through `tabSelection`.
    @State private var scrolledIndex: Int? = 0

    var body: some View {
        // A horizontal paging ScrollView keeps the left/right swipe between the five root screens
        // *without* the paged TabView we used before. That TabView is a UIPageViewController, which
        // keeps adjacent pages' NavigationStacks mounted at once; when two large-title nav bars
        // overlap mid-swipe UIKit crashes with "nest wrapped navigation controllers". A plain
        // ScrollView has no page/navigation controller to nest, so each tab's NavigationStack keeps
        // its large title and back stack while the swipe still works. Inner Lists still scroll
        // vertically since the pager only claims horizontal drags.
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    page(DashboardView(), size: proxy.size, index: 0)
                    page(AccountListView(), size: proxy.size, index: 1)
                    page(TransactionListView(), size: proxy.size, index: 2)
                    page(BudgetListView(), size: proxy.size, index: 3)
                    page(MoreView(), size: proxy.size, index: 4)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledIndex)
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: tabSelection)
        }
    }

    /// Bridges the floating bar's `Int` selection to the pager's optional `scrolledIndex`. Reading
    /// reflects the page the pager settled on; writing (a bar tap) scrolls the pager there. Driving
    /// both directions off one state avoids the two-way `onChange` sync that updated `selection` and
    /// `scrolledIndex` back and forth within a frame ("action tried to update multiple times per
    /// frame").
    private var tabSelection: Binding<Int> {
        Binding(
            get: { scrolledIndex ?? 0 },
            set: { newValue in
                guard scrolledIndex != newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) { scrolledIndex = newValue }
            }
        )
    }

    /// One full-screen page in the pager, tagged with its index so `scrollPosition` can track and
    /// drive it.
    private func page<Content: View>(_ content: Content, size: CGSize, index: Int) -> some View {
        content
            .frame(width: size.width, height: size.height)
            .id(index)
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
