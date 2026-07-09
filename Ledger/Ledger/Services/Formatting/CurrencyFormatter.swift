import Foundation

enum CurrencyFormatter {
    static func string(from amount: Decimal, currencyCode: String = "CAD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_CA")
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
