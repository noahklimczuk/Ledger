import SwiftUI
import SwiftData
import Observation

/// The app's root: a native `TabView` over the five primary screens. The visual tab bar renders as
/// a floating Liquid Glass pill with Home in the centre: Wellness · Activity · Home · Budgets ·
/// More. Each tab supplies its own `NavigationStack`, so large titles and back stacks stay per-tab.
/// Accounts and Recurring live under Home (via the balance card) and More, matching the `bloom-ios`
/// rendering.
struct RootTabView: View {
    @Environment(AppLockService.self) private var lockService
    /// The selected tab index. Visual bar order is Wellness(0), Activity(1), Home(2), Budgets(3), More(4)
    /// so Home sits in the centre.
    @State private var selection = 2
    @State private var isPresentingAskLedger = false
    private static let tabCount = 5

    var body: some View {
        TabView(selection: $selection) {
            Tab("Wellness", systemImage: "leaf.fill", value: 0) {
                FinancialWellnessView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Activity", systemImage: "chart.bar.xaxis", value: 1) {
                TransactionListView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Home", systemImage: "house.fill", value: 2) {
                DashboardView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Budgets", systemImage: "chart.pie.fill", value: 3) {
                BudgetListView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("More", systemImage: "square.grid.2x2.fill", value: 4) {
                MoreView().toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .padding(.bottom, 1)
        // Hide the system tab bar so only the custom floating pill shows. The modifier must sit on
        // *each tab's content* — applying it at the `TabView` level doesn't take on iOS 26, which left
        // the native bar visible *behind* the custom pill (the double-bar bug). The custom bar is
        // floated higher via `safeAreaInset`, which also reserves its space so scrolling content
        // clears it. A 1-point bottom padding on `TabView` forces SwiftUI to break contact with the
        // bottom safe area, so the inset actually pushes scrollable content up.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
        .onChange(of: lockService.isUnlocked) { _, isUnlocked in
            if isUnlocked { selection = 2 }
        }
        .overlay(alignment: .bottomTrailing) {
            if selection != 2 {
                AskLedgerButton(isPresented: $isPresentingAskLedger)
                    .padding(.trailing, 12)
                    .padding(.bottom, 88)
            }
        }
        .sheet(isPresented: $isPresentingAskLedger) {
            AskLedgerView(month: .now)
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

/// A true Liquid Glass floating tab bar with five equal-width tabs.
///
/// Modeled on the App Store tab bar: an extremely translucent frosted pill that lets the screen
/// behind it show through, with the Bloom top sheen, a soft bottom inner glow, and a hairline
/// edge. The selected tab gets a periwinkle wash, bold weight, and a filled SF Symbol. There is no
/// giant centre FAB — Home sits in the middle as a regular tab.
private struct FloatingTabBar: View {
    @Binding var selection: Int

    /// Visual order: Wellness · Activity · Home · Budgets · More. Home sits in the centre.
    private let items: [(title: String, icon: String, selected: String)] = [
        ("Wellness", "heart", "heart.fill"),
        ("Activity", "chart.bar", "chart.bar.fill"),
        ("Home", "house", "house.fill"),
        ("Budgets", "wallet.bifold", "wallet.bifold.fill"),
        ("More", "ellipsis", "ellipsis"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
                tabButton(index)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(glassBar)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(Motion.bouncy, value: selection)
    }

    private var glassBar: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
            Capsule(style: .continuous)
                .fill(Color.appSurface.opacity(0.06))
            // ::before top sheen (30% white -> transparent by 44%)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.32), location: 0),
                            .init(color: Color.white.opacity(0.06), location: 0.44),
                            .init(color: Color.clear, location: 0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
            // bottom inner highlight (inset 0 -8px 18px var(--sl))
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0),
                            .init(color: Color.white.opacity(0.04), location: 0.55),
                            .init(color: Color.white.opacity(0.10), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 14)
    }

    private func tabButton(_ index: Int) -> some View {
        let item = items[index]
        let isSelected = selection == index
        return Button {
            Haptics.tap(.soft)
            selection = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? item.selected : item.icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(item.title)
                    .font(AppFont.scaled(10, relativeTo: .caption2, weight: isSelected ? .bold : .semibold))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Accent.wellness.deep) : AnyShapeStyle(Color.primary.opacity(0.55)))
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    selectedPill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectedPill() -> some View {
        Capsule(style: .continuous)
            .fill(Accent.wellness.base.opacity(0.13))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}

private struct MoreView: View {
    @AppStorage("ledgerColorScheme") private var colorSchemeRaw = AppColorScheme.system.rawValue
    @State private var isPresentingCheckIn = false

    private var colorScheme: Binding<AppColorScheme> {
        Binding(
            get: { AppColorScheme(rawValue: colorSchemeRaw) ?? .system },
            set: { colorSchemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MoreGroup(title: "Routine") {
                        MoreButton(title: "Daily Check-In", icon: "✅") {
                            isPresentingCheckIn = true
                        }
                    }

                    MoreGroup(title: "Insights") {
                        MoreLink(title: "Ask Ledger", icon: "✨") {
                            AskLedgerView(month: .now)
                        }
                        MoreDivider()
                        MoreLink(title: "Reports", icon: "📊") {
                            ReportsView()
                        }
                        MoreDivider()
                        MoreLink(title: "Recurring", icon: "🔄") {
                            RecurringView()
                        }
                    }

                    MoreGroup(title: "Planning") {
                        MoreLink(title: "Savings Goals", icon: "🎯") {
                            SavingsGoalsView()
                        }
                        MoreDivider()
                        MoreLink(title: "Debt Tracker", icon: "💳") {
                            DebtListView()
                        }
                        MoreDivider()
                        MoreLink(title: "Bill Reminders", icon: "🔔") {
                            BillRemindersView()
                        }
                    }

                    MoreGroup(title: "Organize") {
                        MoreLink(title: "Categories", icon: "🏷️") {
                            CategoryEditorView()
                        }
                    }

                    MoreGroup(title: "Data Sources") {
                        MoreLink(title: "Connect Wealthsimple", icon: "🔗") {
                            IntegrationsSettingsView()
                        }
                        MoreDivider()
                        MoreLink(title: "Import CSV / OFX", icon: "📥") {
                            CSVImportView()
                        }
                    }

                    MoreGroup(title: "Appearance") {
                        Picker("Appearance", selection: colorScheme) {
                            ForEach(AppColorScheme.allCases) { scheme in
                                Text(scheme.displayName).tag(scheme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("More")
            .accent(.dashboard)
            .accentWash(.dashboard)
            .sheet(isPresented: $isPresentingCheckIn) {
                DailyCheckInView()
            }
        }
    }
}

/// A titled, Bloom-styled group of More actions. The card holds the rows; the headline keeps the
/// screen's editorial hierarchy.
private struct MoreGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeadline(title)
            VStack(spacing: 0) {
                content
            }
            .card()
        }
    }
}

private struct MoreRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            BloomRowIcon(emoji: icon, size: 40)
            Text(title)
                .font(.appSubheadline.weight(.semibold))
            Spacer()
            Text("›")
                .font(.appCaption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct MoreLink<Destination: View>: View {
    let title: String
    let icon: String
    let destination: Destination

    init(title: String, icon: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.icon = icon
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            MoreRow(title: title, icon: icon)
        }
        .buttonStyle(.pressable)
    }
}

private struct MoreButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MoreRow(title: title, icon: icon)
        }
        .buttonStyle(.pressable)
    }
}

private struct MoreDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.appHairline)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

/// A compact, floating Ask Ledger dot. The "Ask Ledger" badge is pinned to the top-right corner of
/// the dot and offset so it overlaps the dot and extends into the screen corner. Hidden on Home
/// because the Dashboard already has its own Ask Ledger card.
private struct AskLedgerButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            Haptics.tap(.soft)
            isPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 50, height: 50)
                    .shadow(color: Accent.insights.base.opacity(0.35), radius: 10, x: 0, y: 5)
                Circle()
                    .fill(Accent.insights.gradient)
                    .frame(width: 46, height: 46)
                Text("✨")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .topTrailing) {
                Text("Ask Ledger")
                    .font(.appCaption2.weight(.heavy))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appSurface, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.appHairline, lineWidth: 1)
                    )
                    .shadow(color: Color.bloomShadow, radius: 6, x: 0, y: 3)
                    .offset(x: 6, y: -6)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Ask Ledger")
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
