import Foundation

enum CurrencyFormatter {
    /// NumberFormatter construction is expensive and this runs for every money label in every
    /// list row, so cache one formatter per currency. The module defaults to MainActor isolation,
    /// which is what makes the shared cache safe.
    private static var formatters: [String: NumberFormatter] = [:]

    static func string(from amount: Decimal, currencyCode: String = "CAD") -> String {
        let formatter: NumberFormatter
        if let cached = formatters[currencyCode] {
            formatter = cached
        } else {
            formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            formatter.locale = Locale(identifier: "en_CA")
            formatters[currencyCode] = formatter
        }
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
