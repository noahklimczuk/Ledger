import Charts
import SwiftUI

/// One slice of an `InteractiveDonutChart`.
struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let value: Decimal
    let color: Color
    /// When false the slice/row still shows but isn't tappable — e.g. an "Uncategorized" or
    /// "Other" bucket that has no single category to drill into.
    var isSelectable: Bool = true
}

/// A reusable interactive doughnut (Swift Charts `SectorMark` + angle selection). Tapping a slice
/// or its legend row highlights it; when `onSelect` is set and the segment is selectable it calls
/// back so the caller can drill in. Without `onSelect`, a tap just shows that slice's label and
/// amount in the centre.
struct InteractiveDonutChart: View {
    let segments: [DonutSegment]
    var centerCaption: String?
    /// Overrides the centre value text (defaults to the formatted total) — used e.g. by the
    /// spent-vs-remaining gauge to show a percentage.
    var centerValueText: String?
    var showLegend: Bool = true
    /// When false the ring is a passive display: it ignores taps entirely, so a pure gauge (which
    /// shows a fixed value in the centre) can't have that value replaced by a stuck slice highlight.
    var isInteractive: Bool = true
    var onSelect: ((DonutSegment) -> Void)?

    @State private var selectedValue: Double?

    init(
        segments: [DonutSegment],
        centerCaption: String? = nil,
        centerValueText: String? = nil,
        showLegend: Bool = true,
        isInteractive: Bool = true,
        onSelect: ((DonutSegment) -> Void)? = nil
    ) {
        self.segments = segments
        self.centerCaption = centerCaption
        self.centerValueText = centerValueText
        self.showLegend = showLegend
        self.isInteractive = isInteractive
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 16) {
            ring
            if showLegend {
                legend
            }
        }
    }

    private var total: Decimal { segments.reduce(0) { $0 + $1.value } }

    /// A spoken rundown of every slice, e.g. "Groceries, $420.00; Rent, $1,500.00".
    private var accessibilitySummary: String {
        segments
            .map { "\($0.label), \(CurrencyFormatter.string(from: $0.value))" }
            .joined(separator: "; ")
    }

    private var selectedSegment: DonutSegment? {
        guard let selectedValue else { return nil }
        var running = 0.0
        for segment in segments {
            running += segment.value.donutDouble
            if selectedValue <= running { return segment }
        }
        return segments.last
    }

    private var ring: some View {
        Chart(segments) { segment in
            SectorMark(
                angle: .value("Amount", segment.value.donutDouble),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(segment.color)
            .opacity(selectedSegment == nil || selectedSegment?.id == segment.id ? 1 : 0.35)
        }
        // A passive gauge binds selection to a no-op so a tap can't leave a persistent highlight.
        .chartAngleSelection(value: isInteractive ? $selectedValue : .constant(nil))
        .chartLegend(.hidden)
        .frame(height: 200)
        // The ring is a VoiceOver dead spot on its own (the legend, when shown, carries the detail),
        // so give it a spoken summary of every slice for the no-legend cases like the gauge.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(centerCaption ?? "Breakdown")
        .accessibilityValue(accessibilitySummary)
        .overlay { centerLabel }
        .animation(.easeInOut(duration: 0.2), value: selectedSegment?.id)
        .onChange(of: selectedValue) { _, _ in
            // With a drill-down callback a tap navigates rather than leaving a persistent highlight.
            guard let onSelect, let segment = selectedSegment else { return }
            selectedValue = nil
            if segment.isSelectable { onSelect(segment) }
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let segment = selectedSegment {
                Text(segment.label)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(CurrencyFormatter.string(from: segment.value))
                    .font(.appHeadline)
            } else {
                if let centerCaption {
                    Text(centerCaption)
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                Text(centerValueText ?? CurrencyFormatter.string(from: total))
                    .font(.appTitle3.bold())
            }
        }
        .padding(.horizontal, 12)
        .multilineTextAlignment(.center)
    }

    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(segments) { segment in
                legendRow(segment)
                if segment.id != segments.last?.id {
                    Divider().padding(.leading, 22)
                }
            }
        }
    }

    @ViewBuilder
    private func legendRow(_ segment: DonutSegment) -> some View {
        let tappable = onSelect != nil && segment.isSelectable
        if tappable {
            Button {
                onSelect?(segment)
            } label: {
                rowContent(segment, showChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(segment, showChevron: false)
        }
    }

    private func rowContent(_ segment: DonutSegment, showChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(segment.color).frame(width: 10, height: 10)
            Text(segment.label)
                .font(.appSubheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(CurrencyFormatter.string(from: segment.value))
                .font(.appSubheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            if showChevron {
                Text("›")
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private extension Decimal {
    var donutDouble: Double { (self as NSDecimalNumber).doubleValue }
}
