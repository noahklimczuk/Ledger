import SwiftUI

// MARK: - Tone → colour

extension AskLedgerTone {
    var color: Color {
        switch self {
        case .positive: Palette.green
        case .caution:  Palette.peachDeep
        case .info:     Palette.periDeep
        case .neutral:  Color.primary
        }
    }
}

// MARK: - Prompt suggestion card (landing screen)

/// A tappable starter prompt on the Ask Ledger landing screen.
struct PromptSuggestionCard: View {
    let icon: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: icon, accent: .insights, size: 36, filled: false)
                Text(text)
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Message

/// One conversation turn — a user question (gradient bubble) or an assistant answer (clay card of
/// structured blocks, plus suggested actions and follow-ups).
struct AskLedgerMessageView: View {
    let turn: AskLedgerTurn
    /// Ask a follow-up question, staying in the conversation.
    let onSend: (String) -> Void

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Accent.insights.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Accent.insights.base.opacity(0.3), radius: 10, y: 5)
            }
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                AskLedgerSeal()
                if turn.isThinking {
                    ThinkingBubble()
                } else if let response = turn.response {
                    responseCard(response)
                }
                Spacer(minLength: 8)
            }
        }
    }

    private func responseCard(_ response: AskLedgerResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(response.blocks.enumerated()), id: \.offset) { _, block in
                AskLedgerBlockView(block: block)
            }
            if !response.actions.isEmpty {
                ResponseActionBar(actions: response.actions, onSend: onSend)
            }
            if !response.followUps.isEmpty {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRY ASKING")
                        .font(.appCaption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                    ForEach(response.followUps, id: \.self) { prompt in
                        Button { onSend(prompt) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right").font(.caption2.weight(.bold))
                                Text(prompt).font(.appSubheadline)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Accent.insights.deep)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// The little Ask Ledger seal that leads each answer.
struct AskLedgerSeal: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Accent.insights.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: Accent.insights.base.opacity(0.35), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Thinking indicator

struct ThinkingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Accent.insights.base)
                    .frame(width: 8, height: 8)
                    .scaleEffect(0.6 + 0.4 * pulse(index))
                    .opacity(0.4 + 0.6 * pulse(index))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card(padding: 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { phase = 1 } }
        .accessibilityLabel("Thinking")
    }
    private func pulse(_ index: Int) -> Double {
        let shifted = phase - Double(index) * 0.2
        return max(0, sin(shifted * .pi))
    }
}

// MARK: - Blocks

/// Renders one structured answer block. Each case is its own small reusable view.
struct AskLedgerBlockView: View {
    let block: AskLedgerBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text).font(.appBody).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        case .headline(let text):
            Text(text).font(.appTitle3.weight(.heavy)).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
        case .metrics(let metrics):
            AIMetricRow(metrics: metrics)
        case .insight(let insight):
            AIInsightBlock(insight: insight)
        case .bars(let title, let bars):
            AIBarsBlock(title: title, bars: bars)
        case .budget(let title, let lines):
            AIBudgetBlock(title: title, lines: lines)
        case .subscriptions(let monthly, let lines):
            AISubscriptionsBlock(monthly: monthly, lines: lines)
        case .forecast(let forecast):
            AIForecastBlock(forecast: forecast)
        case .progress(let title, let fraction, let caption, let tone):
            AIProgressBlock(title: title, fraction: fraction, caption: caption, tone: tone)
        }
    }
}

struct AIMetricRow: View {
    let metrics: [AskLedgerMetric]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.label.uppercased())
                        .font(.appCaption2.weight(.bold)).tracking(0.4).foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.appTitle3.weight(.heavy)).foregroundStyle(metric.tone.color)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if let caption = metric.caption {
                        Text(caption).font(.appCaption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
        }
    }
}

struct AIInsightBlock: View {
    let insight: AskLedgerInsightItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(insight.tone.color)
                .frame(width: 34, height: 34)
                .background(insight.tone.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.appSubheadline.weight(.bold))
                Text(insight.message).font(.appFootnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(insight.tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

struct AIBarsBlock: View {
    let title: String
    let bars: [AskLedgerBar]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.appCaption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                HStack(spacing: 10) {
                    Text(bar.label).font(.appCaption.weight(.semibold)).frame(width: 78, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(bar.isOver ? AnyShapeStyle(Palette.coral) : AnyShapeStyle(Accent.insights.gradient))
                                .frame(width: max(geo.size.width * min(max(bar.value, 0), 1), 8))
                        }
                    }
                    .frame(height: 10)
                    Text(bar.valueText).font(.appCaption.weight(.bold)).monospacedDigit().frame(width: 68, alignment: .trailing)
                }
            }
        }
    }
}

struct AIBudgetBlock: View {
    let title: String
    let lines: [AskLedgerBudgetLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.appCaption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(line.name).font(.appSubheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("\(line.spentText) / \(line.allocatedText)")
                            .font(.appCaption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(line.isOver ? Palette.coral : .secondary)
                    }
                    ClayChannel(progress: line.progress, isOver: line.isOver, fillAccent: .insights, height: 12)
                }
            }
        }
    }
}

struct AISubscriptionsBlock: View {
    let monthly: String
    let lines: [AskLedgerSubLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SUBSCRIPTIONS").font(.appCaption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer()
                Text("\(monthly)/mo").font(.appCaption.weight(.heavy)).foregroundStyle(Accent.insights.deep)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 10) {
                    Image(systemName: "repeat").font(.caption.weight(.bold)).foregroundStyle(Accent.insights.base)
                        .frame(width: 28, height: 28)
                        .background(Accent.insights.base.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name).font(.appSubheadline.weight(.semibold))
                        Text(line.cadence).font(.appCaption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if let flag = line.flag {
                        Text(flag).font(.appCaption2.weight(.bold)).foregroundStyle(Palette.peachDeep)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Palette.peach.opacity(0.18), in: Capsule())
                    }
                    Text(line.amountText).font(.appSubheadline.weight(.bold)).monospacedDigit()
                }
            }
        }
    }
}

struct AIForecastBlock: View {
    let forecast: AskLedgerForecast
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(forecast.headline.uppercased()).font(.appCaption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            ForEach(Array(forecast.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack {
                    Text(row.label).font(.appSubheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value).font(.appSubheadline.weight(.bold)).monospacedDigit().foregroundStyle(row.tone.color)
                }
            }
        }
        .padding(14)
        .background(forecast.tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

struct AIProgressBlock: View {
    let title: String
    let fraction: Double
    let caption: String
    let tone: AskLedgerTone
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tone.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(min(max(fraction, 0), 1) * 100))%")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(tone.color)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.appSubheadline.weight(.bold))
                Text(caption).font(.appCaption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Actions

struct ResponseActionBar: View {
    let actions: [AskLedgerAction]
    let onSend: (String) -> Void

    var body: some View {
        FlowChips(actions: actions, onSend: onSend)
    }
}

/// Wraps the action chips; a route chip navigates, an ask chip sends a follow-up.
private struct FlowChips: View {
    let actions: [AskLedgerAction]
    let onSend: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                switch action.kind {
                case .ask(let prompt):
                    Button { onSend(prompt) } label: { chip(action) }
                        .buttonStyle(.pressable)
                case .route(let route):
                    NavigationLink(value: route) { chip(action) }
                        .buttonStyle(.pressable)
                }
            }
        }
    }

    private func chip(_ action: AskLedgerAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.systemImage).font(.caption.weight(.bold))
            Text(action.title).font(.appSubheadline.weight(.semibold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(Accent.insights.deep)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.insights.base.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

// MARK: - Input

struct AskLedgerInput: View {
    @Binding var text: String
    var isDisabled: Bool
    let onSend: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask Ledger anything…", text: $text, axis: .vertical)
                .font(.appBody)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.appSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.appHairline, lineWidth: 1))

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? AnyShapeStyle(Accent.insights.gradient) : AnyShapeStyle(Color.secondary.opacity(0.4)), in: Circle())
                    .shadow(color: canSend ? Accent.insights.base.opacity(0.4) : .clear, radius: 10, y: 5)
            }
            .buttonStyle(.pressable)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var canSend: Bool { !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func send() {
        guard canSend else { return }
        onSend()
    }
}
