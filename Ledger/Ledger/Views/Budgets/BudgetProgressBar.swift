import SwiftUI

struct BudgetProgressBar: View {
    let progress: Double
    let isOverBudget: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(isOverBudget ? Color.red : Color.accentColor)
                    .frame(width: geometry.size.width * min(progress, 1))
            }
        }
        .frame(height: 8)
    }
}
