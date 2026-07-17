import SwiftUI
import SwiftData

/// The Insights tab: a short, refreshed-on-open list of on-device findings. Each card can be
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
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Insights")
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(.title3)
                .foregroundStyle(Color(hex: insight.severity.tintHex))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(insight.message)
                    .font(.footnote)
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
            .tint(.orange)
        }
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
