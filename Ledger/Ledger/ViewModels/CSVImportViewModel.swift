import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CSVImportViewModel {
    enum Stage {
        case chooseFile
        case configure
        case preview
        case complete
    }

    enum FileKind {
        case csv
        case ofx
    }

    struct PreviewRow: Identifiable {
        let id: Int
        let transaction: ImportedTransaction?
        let error: String?
        let isDuplicate: Bool

        var isImportable: Bool { transaction != nil && !isDuplicate }
    }

    private(set) var stage: Stage = .chooseFile
    private(set) var fileKind: FileKind = .csv
    private(set) var fileName: String?
    private(set) var errorMessage: String?

    // CSV configuration
    var hasHeaderRow = true { didSet { recomputeHeaders() } }
    var mapping = CSVColumnMapping()
    private(set) var rawRows: [[String]] = []

    // Target + preview
    private(set) var accounts: [Account] = []
    var targetAccount: Account?
    private(set) var previewRows: [PreviewRow] = []
    private(set) var summary: TransactionImportService.ImportSummary?

    private var ofxRecords: [OFXRecord] = []
    private let modelContext: ModelContext

    let availableDateFormats = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "yyyy/MM/dd", "MMM d, yyyy"]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        accounts = (try? modelContext.fetch(FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
        targetAccount = accounts.first
    }

    var headers: [String] {
        guard !rawRows.isEmpty else { return [] }
        if hasHeaderRow {
            return rawRows[0].enumerated().map { index, value in
                value.trimmingCharacters(in: .whitespaces).isEmpty ? "Column \(index + 1)" : value
            }
        }
        return (0..<rawRows[0].count).map { "Column \($0 + 1)" }
    }

    var dataRows: [[String]] {
        guard !rawRows.isEmpty else { return [] }
        return hasHeaderRow ? Array(rawRows.dropFirst()) : rawRows
    }

    var newCount: Int { previewRows.filter(\.isImportable).count }
    var duplicateCount: Int { previewRows.filter(\.isDuplicate).count }
    var errorCount: Int { previewRows.filter { $0.error != nil }.count }

    // MARK: - File loading

    func fileSelectionFailed(_ message: String) {
        errorMessage = "Couldn't open that file: \(message)"
        stage = .chooseFile
    }

    func load(fileURL: URL) {
        errorMessage = nil
        fileName = fileURL.lastPathComponent

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        guard let text = readText(from: fileURL) else {
            errorMessage = "Couldn't read that file. Make sure it's a plain CSV or OFX export."
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        let looksLikeOFX = ext == "ofx" || ext == "qfx" || text.contains("<STMTTRN>")

        if looksLikeOFX {
            fileKind = .ofx
            ofxRecords = OFXParser.parse(text)
            if ofxRecords.isEmpty {
                errorMessage = "No transactions found in that OFX file."
                return
            }
        } else {
            fileKind = .csv
            rawRows = CSVParser.parse(text)
            guard !rawRows.isEmpty else {
                errorMessage = "That CSV file appears to be empty."
                return
            }
            mapping = CSVColumnMapping.autodetect(headers: headers)
        }

        stage = .configure
    }

    private func readText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1)
    }

    private func recomputeHeaders() {
        guard fileKind == .csv, !rawRows.isEmpty else { return }
        mapping = CSVColumnMapping.autodetect(headers: headers)
    }

    // MARK: - Preview

    var canBuildPreview: Bool {
        guard targetAccount != nil else { return false }
        return fileKind == .ofx || mapping.isComplete
    }

    func buildPreview() {
        guard let account = targetAccount else { return }
        let token = Self.accountToken(for: account)
        let existing = TransactionImportService(modelContext: modelContext).existingExternalIds()

        let mapped: [ImportMappedRow]
        switch fileKind {
        case .csv:
            mapped = CSVTransactionSource(
                dataRows: dataRows,
                mapping: mapping,
                accountToken: token,
                currencyCode: account.currencyCode
            ).map()
        case .ofx:
            mapped = OFXTransactionSource(
                records: ofxRecords,
                accountToken: token,
                currencyCode: account.currencyCode
            ).map()
        }

        // A row is a duplicate if it already exists in the store, or if an earlier row in this
        // same batch already claimed its id (identical fingerprint + occurrence).
        var seenInBatch: Set<String> = []
        previewRows = mapped.map { row in
            var isDuplicate = false
            if let id = row.transaction?.id {
                isDuplicate = existing.contains(id) || seenInBatch.contains(id)
                seenInBatch.insert(id)
            }
            return PreviewRow(id: row.id, transaction: row.transaction, error: row.error, isDuplicate: isDuplicate)
        }

        stage = .preview
    }

    // MARK: - Commit

    func commit() {
        guard let account = targetAccount else { return }
        let importable = previewRows.compactMap { $0.isImportable ? $0.transaction : nil }
        let sourceKind: TransactionSourceKind = fileKind == .ofx ? .ofx : .csv

        do {
            let service = TransactionImportService(modelContext: modelContext)
            summary = try service.importTransactions(importable, into: account, sourceKind: sourceKind)
            stage = .complete
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func backToConfigure() {
        stage = .configure
    }

    /// Stable, launch-independent token for an account. `createdAt` never changes once set and is
    /// effectively unique per account, so identical rows imported into different accounts get
    /// distinct externalIds while re-imports into the same account stay idempotent.
    private static func accountToken(for account: Account) -> String {
        String(account.createdAt.timeIntervalSince1970)
    }
}
