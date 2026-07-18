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
/// custom-pager risk. It's larger than the system bar and lifted up via bottom padding.
///
/// On iOS 26 it re-creates the App Store tab bar's animation as closely as the public glass APIs
/// allow: the bar's glass and the selected-tab glass are *siblings* in one `GlassEffectContainer`
/// (so the highlight reads as a real lens floating in the bar, not a flat tint), and a shared
/// `glassEffectID` makes the container morph that lens between tabs — the liquid "flow" — as the
/// selection changes. Pre-iOS 26 falls back to a material pill with a soft accent capsule.
private struct FloatingTabBar: View {
    @Binding var selection: Int
    /// Ties the selected-tab glass to one identity so the container morphs it between tabs.
    @Namespace private var glassNamespace

    private let items: [(title: String, icon: String)] = [
        ("Dashboard", "house.fill"),
        ("Accounts", "banknote.fill"),
        ("Transactions", "list.bullet"),
        ("Budgets", "chart.pie.fill"),
        ("More", "ellipsis.circle.fill"),
    ]

    var body: some View {
        bar
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
    }

    /// One tab — icon over label, accent-tinted when selected. Sized larger than the system bar.
    private func tabButton(_ index: Int) -> some View {
        let item = items[index]
        return Button {
            selection = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: .medium))
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selection == index ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selection == index ? [.isSelected] : [])
    }

    @ViewBuilder
    private var bar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                ZStack {
                    // The bar pill — a sibling of the selection glass so the two blend into one surface.
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    HStack(spacing: 0) {
                        ForEach(items.indices, id: \.self) { index in
                            tabButton(index)
                                .background {
                                    if selection == index {
                                        Capsule()
                                            .fill(.clear)
                                            .glassEffect(
                                                .regular.tint(Color.accentColor.opacity(0.5)).interactive(),
                                                in: Capsule()
                                            )
                                            .glassEffectID("selection", in: glassNamespace)
                                            .padding(5)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                }
            }
            // Keep the container at its intrinsic height so it can't expand and inflate the inset.
            .fixedSize(horizontal: false, vertical: true)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selection)
        } else {
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    tabButton(index)
                        .background {
                            if selection == index {
                                Capsule().fill(Color.accentColor.opacity(0.15)).padding(.horizontal, 4)
                            }
                        }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selection)
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
