import SwiftUI
import SwiftData

/// A short, refreshed-on-open list of on-device findings. Each card can be
/// dismissed (gone for good) or snoozed (hidden for a week) via swipe. Everything is computed
/// locally from the user's data — nothing is sent anywhere.
struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InsightsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.insights.isEmpty {
                    EmptyStateView(
                        systemImage: "sparkles",
                        title: "You're All Caught Up",
                        message: "As you add and categorize more transactions, Ledger surfaces spending trends, budget warnings, and subscription tips here."
                    )
                } else {
                    List {
                        Section {
                            ForEach(viewModel.insights) { insight in
                                InsightCard(
                                    insight: insight,
                                    onDismiss: { viewModel.dismiss(insight) },
                                    onSnooze: { viewModel.snooze(insight) }
                                )
                            }
                        } footer: {
                            Text("Swipe a card to snooze it for a week or dismiss it. Insights refresh automatically as your data changes.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Insights")
        .accentWash(.insights)
        .accent(.insights)
        .task {
            if viewModel == nil { viewModel = InsightsViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
    }
}

private struct InsightCard: View {
    let insight: Insight
    let onDismiss: () -> Void
    let onSnooze: () -> Void

    private var tint: Color { Color(hex: insight.severity.tintHex) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(AppFont.scaled(15, relativeTo: .subheadline, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.appSubheadline.weight(.bold))
                Text(insight.message)
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDismiss) {
                Label("Dismiss", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onSnooze) {
                Label("Snooze", systemImage: "clock")
            }
            .tint(Palette.amber)
        }
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
