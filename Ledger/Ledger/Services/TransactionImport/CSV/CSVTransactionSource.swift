import CryptoKit
import Foundation

/// One CSV data row after mapping: either a valid transaction or a parse error, kept together
/// so the import preview can show per-row problems instead of silently dropping rows.
struct ImportMappedRow: Identifiable, Sendable {
    let id: Int
    let transaction: ImportedTransaction?
    let error: String?
}

/// `TransactionSource` over a parsed + column-mapped CSV. Accounts aren't defined by a CSV
/// (the user picks the target account), so `fetchAccounts()` is empty and `fetchTransactions`
/// ignores its arguments -- rows already carry everything. The real entry point is `map()`,
/// which the import view-model uses for the dedup preview.
struct CSVTransactionSource: TransactionSource {
    let sourceIdentifier = "csv"

    /// Data rows only (header already removed by the caller).
    let dataRows: [[String]]
    let mapping: CSVColumnMapping
    /// Stable per-account token so identical rows imported into two different accounts don't
    /// collide on `externalId` (dedup is global by externalId).
    let accountToken: String
    let currencyCode: String

    func fetchAccounts() async throws -> [ImportedAccount] { [] }

    func fetchTransactions(accountExternalId: String, since: Date?) async throws -> [ImportedTransaction] {
        map().compactMap(\.transaction)
    }

    func map() -> [ImportMappedRow] {
        var occurrences: [String: Int] = [:]

        return dataRows.enumerated().map { index, row in
            do {
                let transaction = try mapRow(row, occurrences: &occurrences)
                return ImportMappedRow(id: index, transaction: transaction, error: nil)
            } catch let error as MappingError {
                return ImportMappedRow(id: index, transaction: nil, error: error.message)
            } catch {
                return ImportMappedRow(id: index, transaction: nil, error: "Could not read row.")
            }
        }
    }

    private struct MappingError: Error { let message: String }

    private func mapRow(_ row: [String], occurrences: inout [String: Int]) throws -> ImportedTransaction {
        guard let dateColumn = mapping.dateColumn, let rawDate = cell(row, dateColumn),
              let date = ImportValueParsing.date(from: rawDate, preferredFormat: mapping.dateFormat) else {
            throw MappingError(message: "Missing or unrecognized date.")
        }

        let merchant = mapping.merchantColumn.flatMap { cell(row, $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let amount = try mappedAmount(from: row)

        let fingerprint = "\(ISO8601DateFormatter().string(from: date))|\(merchant.lowercased())|\(amount)"
        let occurrence = occurrences[fingerprint, default: 0]
        occurrences[fingerprint] = occurrence + 1

        return ImportedTransaction(
            id: Self.externalId(accountToken: accountToken, prefix: "csv", fingerprint: fingerprint, occurrence: occurrence),
            accountExternalId: accountToken,
            date: date,
            merchant: merchant.isEmpty ? "Imported transaction" : merchant,
            amount: amount,
            currencyCode: currencyCode
        )
    }

    private func mappedAmount(from row: [String]) throws -> Decimal {
        switch mapping.amountMode {
        case .single:
            guard let column = mapping.amountColumn, let raw = cell(row, column),
                  let value = ImportValueParsing.decimal(from: raw) else {
                throw MappingError(message: "Missing or unrecognized amount.")
            }
            return mapping.invertSingleAmountSign ? -value : value

        case .separateInOut:
            let outflow = mapping.outflowColumn.flatMap { cell(row, $0) }.flatMap { ImportValueParsing.decimal(from: $0) }
            let inflow = mapping.inflowColumn.flatMap { cell(row, $0) }.flatMap { ImportValueParsing.decimal(from: $0) }
            guard outflow != nil || inflow != nil else {
                throw MappingError(message: "No money-in or money-out value.")
            }
            // Money out reduces the balance regardless of how the column signs it.
            return (inflow ?? 0) - abs(outflow ?? 0)
        }
    }

    private func cell(_ row: [String], _ column: Int) -> String? {
        guard column >= 0, column < row.count else { return nil }
        let trimmed = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Deterministic id so re-importing the same (or an overlapping) file is idempotent:
    /// same account + same row content + same occurrence index -> same id -> deduped.
    static func externalId(accountToken: String, prefix: String, fingerprint: String, occurrence: Int) -> String {
        let payload = "\(accountToken)|\(fingerprint)|\(occurrence)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return "\(prefix):" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
