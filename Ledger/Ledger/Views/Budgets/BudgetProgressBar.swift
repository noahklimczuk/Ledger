import SwiftUI

struct BudgetProgressBar: View {
    let progress: Double
    let isOverBudget: Bool
    /// 0…1 position of the "you are here" tick — how far through the month we are, so a bar
    /// filled well past the tick reads as overspending pace at a glance. Nil hides the tick.
    var paceMarker: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(isOverBudget ? AnyShapeStyle(Color.red) : AnyShapeStyle(LinearGradient.brand))
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
                if let paceMarker, paceMarker > 0.01, paceMarker < 0.99 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 2, height: 14)
                        .offset(x: geometry.size.width * paceMarker - 1)
                }
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.25), value: progress)
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
