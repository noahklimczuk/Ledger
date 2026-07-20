import SwiftUI
import SwiftData

/// The Financial Wellness screen — Bloom's heart. A single 0–100 score answers "how am I doing?",
/// backed by the factors driving it (savings rate, emergency fund, debt, budget, pace), a six-month
/// trend, and a short "what to tend" list. Everything is computed on-device from the user's own data.
struct FinancialWellnessView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRefreshCoordinator.self) private var refresh
    @State private var viewModel: WellnessViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.result.factors.isEmpty {
                    EmptyStateView(
                        systemImage: "leaf.fill",
                        title: "Your Score Is Growing",
                        message: "Add an account and a few transactions and your Financial Wellness score will bloom here — one number for how healthy your money is."
                    )
                } else {
                    content(viewModel)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Financial Wellness")
        .accent(.wellness)
        .task {
            if viewModel == nil { viewModel = WellnessViewModel(modelContext: modelContext) }
            viewModel?.load()
        }
        .onChange(of: refresh.refreshCount) { _, _ in viewModel?.load() }
    }

    private func content(_ viewModel: WellnessViewModel) -> some View {
        let result = viewModel.result
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                heroCard(result)
                factorsGrid(result)
                if !viewModel.trend.isEmpty {
                    trendCard(viewModel.trend)
                }
                if !result.toTend.isEmpty {
                    tendCard(result.toTend)
                }
                askLedgerCard(result)
            }
            .padding()
        }
        .accentWash(.wellness)
    }

    // MARK: Hero

    private func heroCard(_ result: WellnessResult) -> some View {
        VStack(spacing: 14) {
            WellnessRing(score: result.score, size: 168, lineWidth: 15)
                .padding(.top, 4)
            Text("\(result.state) \(result.stateEmoji)")
                .font(.appTitle2.weight(.heavy))
                .foregroundStyle(Accent.wellness.deep)
            Text(result.summary)
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .card()
    }

    // MARK: Factors

    private func factorsGrid(_ result: WellnessResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("What's behind it")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(result.factors) { factor in
                    factorCard(factor)
                }
            }
        }
    }

    private func factorCard(_ factor: WellnessFactor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(factor.name.uppercased())
                    .font(.appCaption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(factor.pointsLabel)
                    .font(.appCaption2.weight(.heavy))
                    .foregroundStyle(factor.isHelping ? Palette.green : Palette.peachDeep)
            }
            Text(factor.valueText)
                .font(.appTitle3.weight(.heavy))
                .foregroundStyle(factor.isHelping ? Color.primary : Palette.peachDeep)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            AccentProgressBar(fraction: factor.fraction, accent: factor.isHelping ? .wellness : .budgets, height: 8)
            Text(factor.detail)
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .card()
    }

    // MARK: Trend

    private func trendCard(_ values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("Savings rate", subtitle: "Last 6 months")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index == values.count - 1 ? AnyShapeStyle(Accent.wellness.gradient) : AnyShapeStyle(Accent.wellness.base.opacity(0.4)))
                        .frame(height: max(8, CGFloat(values[index]) * 96))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: What to tend

    private func tendCard(_ items: [WellnessFactor]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeadline("What to tend")
            VStack(spacing: 0) {
                ForEach(items) { factor in
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(systemName: factor.systemImage, accent: .budgets, size: 40, filled: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(factor.name)
                                .font(.appSubheadline.weight(.semibold))
                            Text(factor.detail)
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    if factor.id != items.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Ask Ledger

    private func askLedgerCard(_ result: WellnessResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconBadge(systemName: "sparkles", accent: .insights, size: 26)
                Text("ASK LEDGER")
                    .font(.appCaption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Accent.insights.deep)
            }
            Text(projection(for: result))
                .font(.appBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Accent.insights.faintGradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Accent.insights.base.opacity(0.25), lineWidth: 1)
        )
    }

    private func projection(for result: WellnessResult) -> String {
        if let tend = result.toTend.first {
            return "Your score is \(result.score). Tend \(tend.name.lowercased()) this month and you'll climb toward the next band — the rest is already working for you."
        }
        return "Your score is \(result.score) and everything's pulling in the same direction. Keep the habits and you'll hold “\(result.state)”."
    }
}

#Preview {
    NavigationStack {
        FinancialWellnessView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
    .environment(AppRefreshCoordinator())
}
