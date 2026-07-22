import SwiftUI
import SwiftData
import Observation

/// The app's root: a native `TabView` over the five primary screens. The visual tab bar renders as
/// a floating Liquid Glass pill with Home in the centre: Wellness · Budgets · Home · Activity ·
/// More. Each tab supplies its own `NavigationStack`, so large titles and back stacks stay per-tab.
/// Accounts and Recurring live under Home (via the balance card) and More, matching the `bloom-ios`
/// rendering.
struct RootTabView: View {
    @Environment(AppLockService.self) private var lockService
    /// The selected tab index. Visual bar order is Wellness(0), Budgets(1), Home(2), Activity(3), More(4)
    /// so Home sits in the centre.
    @State private var selection = 2
    @State private var isPresentingAskLedger = false
    private static let tabCount = 5

    var body: some View {
        TabView(selection: $selection) {
            Tab("Wellness", systemImage: "leaf.fill", value: 0) {
                FinancialWellnessView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Budgets", systemImage: "chart.pie.fill", value: 1) {
                BudgetListView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Home", systemImage: "house.fill", value: 2) {
                DashboardView().toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Activity", systemImage: "chart.bar.xaxis", value: 3) {
                TransactionListView().toolbarVisibility(.hidden, for: .tabBar)
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
        .overlay(alignment: .topTrailing) {
            AskLedgerButton(isPresented: $isPresentingAskLedger, showLabel: selection != 2)
                .padding(.trailing, 16)
                .padding(.top, 16)
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

/// A floating, pill-shaped tab bar raised off the bottom edge. It only draws the bar and writes the
/// selection binding — the enclosing `TabView` still manages the screens — so it carries none of the
/// custom-pager risk.
///
/// The redesign gives it the app's playful, multi-accent character: the selected tab expands into a
/// label pill filled with that section's signature gradient, the pill springs between tabs with a
/// `matchedGeometryEffect`, the icon does a symbol bounce as it's chosen, and the whole bar casts a
/// soft shadow in the current section's color — so the shell itself announces which area you're in.
private struct FloatingTabBar: View {
    @Binding var selection: Int
    /// Ties the moving selection pill to one identity so it springs between tabs.
    @Namespace private var pill

    /// Visual order: Wellness · Budgets · Home · Activity · More. Home sits in the centre as in the
    /// Bloom rendering.
    private let items: [(title: String, icon: String, accent: Accent)] = [
        ("Wellness", "leaf.fill", .wellness),
        ("Budgets", "chart.pie.fill", .budgets),
        ("Home", "house.fill", .dashboard),
        ("Activity", "chart.bar.xaxis", .transactions),
        ("More", "square.grid.2x2.fill", .insights),
    ]

    private var selectedAccent: Accent { items[selection].accent }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                tabButton(index)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.appSurface)
                .overlay(Capsule(style: .continuous).strokeBorder(Color.appHairline, lineWidth: 1))
        )
        .shadow(color: selectedAccent.base.opacity(0.30), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .animation(Motion.bouncy, value: selection)
    }

    /// One tab: an icon with a tiny label below it. The selected item gets a tinted pill behind it,
    /// and a gentle inset top highlight, matching the Liquid Glass tab bar in the Bloom rendering.
    private func tabButton(_ index: Int) -> some View {
        let item = items[index]
        let isSelected = selection == index
        return Button {
            Haptics.tap(.soft)
            selection = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(AppFont.scaled(20, relativeTo: .headline, weight: .bold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(item.title)
                    .font(.appCaption2.weight(.heavy))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(item.accent.base) : AnyShapeStyle(Color.secondary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(item.accent.base.opacity(0.15))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                        MoreButton(title: "Daily Check-In", icon: "checklist", accent: .checkIn) {
                            isPresentingCheckIn = true
                        }
                    }

                    MoreGroup(title: "Insights") {
                        MoreLink(title: "Ask Ledger", icon: "sparkles", accent: .insights) {
                            AskLedgerView(month: .now)
                        }
                        MoreDivider()
                        MoreLink(title: "Reports", icon: "chart.bar.xaxis", accent: .reports) {
                            ReportsView()
                        }
                        MoreDivider()
                        MoreLink(title: "Recurring", icon: "arrow.triangle.2.circlepath", accent: .recurring) {
                            RecurringView()
                        }
                    }

                    MoreGroup(title: "Planning") {
                        MoreLink(title: "Savings Goals", icon: "target", accent: .goals) {
                            SavingsGoalsView()
                        }
                        MoreDivider()
                        MoreLink(title: "Debt Tracker", icon: "creditcard.trianglebadge.exclamationmark", accent: .debt) {
                            DebtListView()
                        }
                        MoreDivider()
                        MoreLink(title: "Bill Reminders", icon: "bell.badge", accent: .bills) {
                            BillRemindersView()
                        }
                    }

                    MoreGroup(title: "Organize") {
                        MoreLink(title: "Categories", icon: "tag.fill", accent: .categories) {
                            CategoryEditorView()
                        }
                    }

                    MoreGroup(title: "Data Sources") {
                        MoreLink(title: "Connect Wealthsimple", icon: "link", accent: .accounts) {
                            IntegrationsSettingsView()
                        }
                        MoreDivider()
                        MoreLink(title: "Import CSV / OFX", icon: "square.and.arrow.down", accent: .transactions) {
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
    let accent: Accent

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, accent: accent, size: 40)
            Text(title)
                .font(.appSubheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.forward")
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
    let accent: Accent
    let destination: Destination

    init(title: String, icon: String, accent: Accent, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            MoreRow(title: title, icon: icon, accent: accent)
        }
        .buttonStyle(.pressable)
    }
}

private struct MoreButton: View {
    let title: String
    let icon: String
    let accent: Accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MoreRow(title: title, icon: icon, accent: accent)
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

/// A persistent, floating Ask Ledger button. Moved to the top-right so it doesn't compete with the
/// custom tab bar, and kept compact so it fits beside navigation content. On non-Home tabs it shows
/// an attached "Ask Ledger" pill so users know what the sparkle dot does.
private struct AskLedgerButton: View {
    @Binding var isPresented: Bool
    let showLabel: Bool

    var body: some View {
        HStack(spacing: 0) {
            if showLabel {
                Text("Ask Ledger")
                    .font(.appCaption2.weight(.black))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.appSurface)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.appHairline, lineWidth: 1)
                            )
                    )
            }
            Button {
                Haptics.tap(.soft)
                isPresented = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: Accent.insights.base.opacity(0.45), radius: 10, y: 4)
                    Circle()
                        .fill(Accent.insights.gradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(18, relativeTo: .body, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                }
            }
            .buttonStyle(.pressable)
            .zIndex(1)
        }
        .accessibilityLabel("Ask Ledger")
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: LedgerSchema.models, inMemory: true)
        .environment(AppRefreshCoordinator())
}
