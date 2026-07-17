import SwiftUI
import SwiftData

struct RootTabView: View {
    /// The single source of truth for the current tab: the page snapped under the horizontal pager.
    /// A swipe updates it directly; the floating bar reads and writes it through `tabSelection`.
    @State private var scrolledIndex: Int? = 0
    /// Measured height of the floating bar. Each page is shrunk by this so the bar never overlaps
    /// content (previously it sat *on top* via `safeAreaInset`, which didn't reach the inner Lists
    /// nested in the horizontal pager, so their last rows scrolled under the bar).
    ///
    /// Seeded with an estimate close to the real bar height so the very first layout sizes pages
    /// correctly instead of drawing them full-height and popping once the measured height arrives;
    /// `onPreferenceChange` overwrites it with the exact value right after the first layout pass.
    @State private var tabBarHeight: CGFloat = 64

    var body: some View {
        // A horizontal paging ScrollView keeps the left/right swipe between the five root screens
        // *without* the paged TabView we used before. That TabView is a UIPageViewController, which
        // keeps adjacent pages' NavigationStacks mounted at once; when two large-title nav bars
        // overlap mid-swipe UIKit crashes with "nest wrapped navigation controllers". A plain
        // ScrollView has no page/navigation controller to nest, so each tab's NavigationStack keeps
        // its large title and back stack. Inner Lists still scroll vertically.
        //
        // The left/right swipe between tabs is intentionally turned off (`.scrollDisabled(true)`
        // below) so a List row's horizontal swipe-actions can't be stolen by a page turn — the two
        // are the same gesture in the same direction, with no reliable way to arbitrate them. Tabs
        // change via the floating bar, which `scrollPosition` still drives programmatically. Delete
        // that one modifier to bring swipe-between-tabs back; the rest of the pager is unchanged.
        GeometryReader { proxy in
            let pageHeight = max(proxy.size.height - tabBarHeight, 0)
            ScrollView(.horizontal) {
                // Pages are shrunk to leave a strip at the bottom for the floating bar (overlaid
                // below), and pinned to the top so that strip lands where the bar sits.
                //
                // An eager HStack (not LazyHStack) keeps all five pages mounted for the app's life,
                // so each root screen's `@State` — its view model and loaded data — survives while
                // you're on another tab. A LazyHStack discards pages that scroll far enough off-screen
                // and rebuilds them on return, which reset each screen to `viewModel == nil` (a
                // LoadingView flash) and re-ran its fetch on every visit. Mounting all five is safe
                // here: the crash this pager was built to avoid came from the *paged TabView's*
                // UIPageViewController nesting navigation controllers, not from plain NavigationStacks
                // sitting side by side in a ScrollView (adjacent pages already coexist during a swipe).
                HStack(alignment: .top, spacing: 0) {
                    page(DashboardView(), width: proxy.size.width, height: pageHeight, index: 0)
                    page(AccountListView(), width: proxy.size.width, height: pageHeight, index: 1)
                    page(TransactionListView(), width: proxy.size.width, height: pageHeight, index: 2)
                    page(BudgetListView(), width: proxy.size.width, height: pageHeight, index: 3)
                    page(MoreView(), width: proxy.size.width, height: pageHeight, index: 4)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledIndex)
            .scrollIndicators(.hidden)
            // Turns off swipe-between-tabs so it can't hijack a row's swipe-actions. Bar taps still
            // navigate (they drive `scrollPosition` above). Remove this one line to restore swiping.
            .scrollDisabled(true)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Float the bar over the reserved strip (not `safeAreaInset`, which the pager's inner Lists
        // didn't pick up). Measuring its height feeds `tabBarHeight` so the pages shrink to match.
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: tabSelection)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TabBarHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight = $0 }
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

    /// One page in the pager, sized to leave room for the floating bar and tagged with its index so
    /// `scrollPosition` can track and drive it.
    private func page<Content: View>(_ content: Content, width: CGFloat, height: CGFloat, index: Int) -> some View {
        content
            .frame(width: width, height: height)
            .id(index)
    }
}

/// Carries the floating bar's measured height up so `RootTabView` can shrink each page by exactly
/// that much.
private struct TabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
