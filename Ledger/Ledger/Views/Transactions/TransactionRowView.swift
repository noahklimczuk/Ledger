import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    private var categoryColor: Color {
        transaction.category.map { Color(hex: $0.colorHex) } ?? Palette.indigo
    }

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.appBodyMedium)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(DateFormatting.relativeDay(transaction.date))
                    if let categoryName = transaction.category?.name {
                        Text("· \(categoryName)")
                    } else if transaction.isSplit {
                        Text("· Split")
                    }
                }
                .font(.appCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                    .font(.appBody.weight(.heavy))
                    .foregroundStyle(transaction.amount < 0 ? Color.primary : Palette.income)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !transaction.isReviewed {
                    Circle()
                        .fill(Palette.amber)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Needs review")
                }
            }
            // Keep the amount at its natural width so a long merchant truncates instead of squeezing
            // the money label.
            .layoutPriority(1)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    /// A rounded-square badge tinted with the category's own color (a soft top-to-bottom gradient for
    /// a little depth), matching the playful icon-badge language used across the redesign.
    private var categoryIcon: some View {
        let symbol = transaction.category?.sfSymbolName ?? "questionmark.circle.fill"
        let color = categoryColor
        return Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
