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
            AskLedgerButton(isPresented: $isPresentingAskLedger)
                .padding(.trailing, 16)
                .padding(.bottom, 110)
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

/// A floating Liquid Glass tab bar raised off the bottom edge. It only draws the bar and writes the
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

    /// Visual order: Wellness · Activity · Home · Budgets · More. Home sits in the centre as in the
    /// Bloom rendering.
    private let items: [(title: String, icon: String, accent: Accent)] = [
        ("Wellness", "leaf.fill", .wellness),
        ("Activity", "chart.bar.xaxis", .transactions),
        ("Home", "house.fill", .dashboard),
        ("Budgets", "chart.pie.fill", .budgets),
        ("More", "square.grid.2x2.fill", .insights),
    ]

    private var selectedAccent: Accent { items[selection].accent }

    var body: some View {
        HStack(spacing: 2) {
            tabButton(0)
            tabButton(1)
            homeButton
            tabButton(3)
            tabButton(4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(glassBar)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .animation(Motion.bouncy, value: selection)
    }

    /// The centre Home tab as a raised FAB: a periwinkle gradient rounded square that floats above
    /// the bar, just like the Bloom rendering's centre action button.
    private var homeButton: some View {
        let isSelected = selection == 2
        return Button {
            Haptics.tap(.soft)
            selection = 2
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appSurface.opacity(0.55))
                    .frame(width: 58, height: 58)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.green, Palette.greenDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                    .shadow(color: Palette.green.opacity(0.35), radius: 12, x: 0, y: 6)
                Image(systemName: "house.fill")
                    .font(AppFont.scaled(25, relativeTo: .title2, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)
            .offset(y: isSelected ? -24 : -18)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
    }

    /// The Liquid Glass shell: a material blur tinted with the app surface, a soft top highlight,
    /// and a translucent white edge so it reads as a raised clay bar over the content behind it.
    private var glassBar: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
            Capsule(style: .continuous)
                .fill(Color.appSurface.opacity(0.55))
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.22), location: 0),
                            .init(color: Color.white.opacity(0.05), location: 0.4),
                            .init(color: Color.clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.5)
        }
        .shadow(color: selectedAccent.base.opacity(0.28), radius: 20, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
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
                    .font(AppFont.scaled(19, relativeTo: .headline, weight: .bold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(item.title)
                    .font(AppFont.scaled(10, relativeTo: .caption2, weight: .heavy))
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(item.accent.base) : AnyShapeStyle(Color.secondary.opacity(0.75)))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    selectedPill(for: item)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func selectedPill(for item: (title: String, icon: String, accent: Accent)) -> some View {
        Capsule(style: .continuous)
            .fill(item.accent.base.opacity(0.14))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.5)
            )
            .matchedGeometryEffect(id: "pill", in: pill)
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

/// A persistent, floating Ask Ledger button. Sits above the custom tab bar in the bottom-right so
/// it's reachable without fighting the navigation bar, and pulses to invite a tap.
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
                    .frame(width: 62, height: 62)
                    .shadow(color: Accent.insights.base.opacity(0.45), radius: 14, x: 0, y: 8)
                Circle()
                    .fill(Accent.insights.gradient)
                    .frame(width: 58, height: 58)
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(26, relativeTo: .body, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)
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
