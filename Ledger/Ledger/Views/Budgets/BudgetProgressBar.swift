import SwiftUI

struct BudgetProgressBar: View {
    /// Draws in the current screen's section accent, so the same bar reads orange on Budgets, etc.
    @Environment(\.accent) private var accent
    let progress: Double
    let isOverBudget: Bool
    /// 0…1 position of the "you are here" tick — how far through the month we are, so a bar
    /// filled well past the tick reads as overspending pace at a glance. Nil hides the tick.
    var paceMarker: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(isOverBudget ? AnyShapeStyle(Palette.expense) : AnyShapeStyle(accent.gradient))
                    .frame(width: max(geometry.size.width * min(max(progress, 0), 1), progress > 0 ? 10 : 0))
                if let paceMarker, paceMarker > 0.01, paceMarker < 0.99 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: 16)
                        .offset(x: geometry.size.width * paceMarker - 1)
                }
            }
        }
        .frame(height: 12)
        .animation(Motion.snappy, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget used")
        .accessibilityValue(isOverBudget ? "Over budget, \(Int(progress * 100)) percent" : "\(Int(progress * 100)) percent")
    }
}

#Preview {
    VStack(spacing: 20) {
        BudgetProgressBar(progress: 0.35, isOverBudget: false, paceMarker: 0.6)
        BudgetProgressBar(progress: 0.9, isOverBudget: false, paceMarker: 0.6)
        BudgetProgressBar(progress: 1.2, isOverBudget: true, paceMarker: 0.6)
    }
    .padding()
}
