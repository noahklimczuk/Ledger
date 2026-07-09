import Foundation

/// Describes how columns in a CSV map onto a transaction. Banks disagree on layout, so this
/// supports both a single signed "Amount" column and separate outflow/inflow columns, plus a
/// sign-inversion toggle for exports that list spending as a positive number.
struct CSVColumnMapping: Sendable, Equatable {
    enum AmountMode: String, Sendable, CaseIterable, Identifiable {
        case single          // one signed amount column
        case separateInOut   // separate money-out / money-in columns

        var id: String { rawValue }
        var label: String {
            switch self {
            case .single: "Single amount column"
            case .separateInOut: "Separate in / out columns"
            }
        }
    }

    var dateColumn: Int?
    var merchantColumn: Int?
    var amountMode: AmountMode = .single
    var amountColumn: Int?
    var outflowColumn: Int?
    var inflowColumn: Int?
    /// When true, a positive value in the single amount column is treated as money out.
    var invertSingleAmountSign = false
    var dateFormat = "yyyy-MM-dd"

    var isComplete: Bool {
        guard dateColumn != nil, merchantColumn != nil else { return false }
        switch amountMode {
        case .single: return amountColumn != nil
        case .separateInOut: return outflowColumn != nil || inflowColumn != nil
        }
    }

    /// Best-effort guess of the mapping from header names. Anything it can't infer is left nil
    /// for the user to set in the mapping UI.
    static func autodetect(headers: [String]) -> CSVColumnMapping {
        var mapping = CSVColumnMapping()
        let normalized = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        func firstIndex(containingAny needles: [String]) -> Int? {
            normalized.firstIndex { header in needles.contains { header.contains($0) } }
        }

        mapping.dateColumn = firstIndex(containingAny: ["date"])
        mapping.merchantColumn = firstIndex(containingAny: ["description", "merchant", "payee", "name", "detail", "memo", "transaction"])

        let outflow = firstIndex(containingAny: ["debit", "withdrawal", "money out", "paid out", "spent", "outflow"])
        let inflow = firstIndex(containingAny: ["credit", "deposit", "money in", "paid in", "received", "inflow"])

        if outflow != nil || inflow != nil {
            mapping.amountMode = .separateInOut
            mapping.outflowColumn = outflow
            mapping.inflowColumn = inflow
        } else {
            mapping.amountMode = .single
            mapping.amountColumn = firstIndex(containingAny: ["amount", "value"])
        }

        return mapping
    }
}
