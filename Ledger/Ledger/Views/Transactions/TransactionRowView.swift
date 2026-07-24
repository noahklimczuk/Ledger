import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.appSubheadline.weight(.heavy))
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
                    .font(.appSubheadline.weight(.heavy))
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

    /// Bloom row icon: a neutral clay emoji badge sized to the transaction row.
    private var categoryIcon: some View {
        BloomRowIcon(
            emoji: transaction.category?.displayIcon ?? BloomEmoji.merchantEmoji(name: transaction.merchant),
            size: 40
        )
    }
}
