import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(DateFormatting.relativeDay(transaction.date))
                    if let categoryName = transaction.category?.name {
                        Text("· \(categoryName)")
                    } else if transaction.isSplit {
                        Text("· Split")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.account?.currencyCode ?? "CAD"))
                    .fontWeight(.semibold)
                    .foregroundStyle(transaction.amount < 0 ? Color.primary : Color.green)
                if !transaction.isReviewed {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Needs review")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var categoryIcon: some View {
        let symbol = transaction.category?.sfSymbolName ?? "questionmark.circle"
        let color = transaction.category.map { Color(hex: $0.colorHex) } ?? .gray
        return Image(systemName: symbol)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}
