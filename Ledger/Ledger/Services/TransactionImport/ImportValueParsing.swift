import Foundation

/// Shared parsing of the messy human-entered strings that show up in CSV/OFX exports:
/// currency amounts (with symbols, thousands separators, parentheses-negatives) and dates
/// (across the handful of formats Canadian banks emit). Kept in one place so CSV and OFX
/// import behave identically.
enum ImportValueParsing {
    /// Parses "$1,234.56", "(45.00)", "-12.30", "  20.00 " etc. into a signed Decimal.
    /// Parentheses and a leading minus both mean negative. Thousands separators are stripped;
    /// the decimal separator is assumed to be a period (matches Wealthsimple / most CA bank exports).
    static func decimal(from raw: String) -> Decimal? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        var isNegative = false
        if value.hasPrefix("(") && value.hasSuffix(")") {
            isNegative = true
            value = String(value.dropFirst().dropLast())
        }

        value = value.replacingOccurrences(of: "$", with: "")
        value = value.replacingOccurrences(of: " ", with: "")
        value = value.replacingOccurrences(of: ",", with: "")

        if value.hasPrefix("-") {
            isNegative = true
            value = String(value.dropFirst())
        } else if value.hasPrefix("+") {
            value = String(value.dropFirst())
        }

        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US")) else { return nil }
        return isNegative ? -decimal : decimal
    }

    private static let fallbackDateFormats = [
        "yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy",
        "MMM d, yyyy", "d MMM yyyy", "MMMM d, yyyy", "yyyyMMdd"
    ]

    /// Tries `preferredFormat` first, then a set of common fallbacks, then ISO8601.
    static func date(from raw: String, preferredFormat: String?) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.timeZone = TimeZone(identifier: "UTC")

        var formats = fallbackDateFormats
        if let preferredFormat, !preferredFormat.isEmpty {
            formats.insert(preferredFormat, at: 0)
        }

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: trimmed)
    }
}
