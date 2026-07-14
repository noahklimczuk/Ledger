import Foundation
import SwiftData

/// Detects recurring charges/income from transaction history and reconciles them into the stored
/// `RecurringSeries` set. Signal is regularity of spacing: a merchant whose transactions land at a
/// consistent cadence (weekly/biweekly/monthly/quarterly/yearly) with ≥3 occurrences is recurring;
/// irregular high-frequency merchants (groceries, restaurants) fail the regularity check.
/// Not actor-isolated — it only touches its `ModelContext` and pure date/amount logic, so it runs on
/// whatever executor its context belongs to (the main context from views, or a background context
/// during the off-main auto-sync). `@MainActor` callers can still use it inline.
final class RecurringDetectionService {
    private let modelContext: ModelContext
    private let minimumOccurrences = 3

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    struct Detected {
        let merchantKey: String
        let displayName: String
        let averageAmount: Decimal
        let cadence: RecurrenceCadence
        let lastOccurrence: Date
        let occurrenceCount: Int
    }

    /// Re-runs detection and upserts results. User `isIgnored` choices are preserved; series that
    /// are no longer detected (and weren't ignored) are removed.
    func refresh() {
        let transactions = ((try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? [])
            .filter(\.countsTowardTotals)
            // Transfers between accounts aren't bills/subscriptions, so keep them out of detection.
            .filter { !$0.isTransfer }
        let detected = detect(in: transactions)
        let detectedKeys = Set(detected.map(\.merchantKey))

        let existing = (try? modelContext.fetch(FetchDescriptor<RecurringSeries>())) ?? []
        var existingByKey: [String: RecurringSeries] = [:]
        for series in existing { existingByKey[series.merchantKey] = series }

        for item in detected {
            let nextExpected = item.cadence.nextDate(after: item.lastOccurrence)
            if let series = existingByKey[item.merchantKey] {
                series.displayName = item.displayName
                series.averageAmount = item.averageAmount
                series.cadence = item.cadence
                series.lastOccurrence = item.lastOccurrence
                series.nextExpected = nextExpected
                series.occurrenceCount = item.occurrenceCount
                series.updatedAt = .now
            } else {
                modelContext.insert(RecurringSeries(
                    merchantKey: item.merchantKey,
                    displayName: item.displayName,
                    averageAmount: item.averageAmount,
                    cadence: item.cadence,
                    lastOccurrence: item.lastOccurrence,
                    nextExpected: nextExpected,
                    occurrenceCount: item.occurrenceCount
                ))
            }
        }

        // Drop series that dropped out of detection, unless the user explicitly ignored them.
        for series in existing where !detectedKeys.contains(series.merchantKey) && !series.isIgnored {
            modelContext.delete(series)
        }

        try? modelContext.save()
    }

    // MARK: - Detection

    func detect(in transactions: [Transaction]) -> [Detected] {
        var groups: [String: [Transaction]] = [:]
        for transaction in transactions {
            let key = Self.normalizeMerchant(transaction.merchant)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(transaction)
        }

        return groups.compactMap { key, group -> Detected? in
            guard group.count >= minimumOccurrences else { return nil }
            let sorted = group.sorted { $0.date < $1.date }

            let gaps = zip(sorted, sorted.dropFirst()).map { current, next in
                next.date.timeIntervalSince(current.date) / 86_400
            }
            guard let median = Self.median(gaps), let cadence = RecurrenceCadence.classify(medianGapDays: median) else {
                return nil
            }

            // Require most gaps to sit near the cadence, so irregular merchants are excluded.
            let tolerance = Double(cadence.approximateDays) * 0.4
            let regularGaps = gaps.filter { abs($0 - Double(cadence.approximateDays)) <= tolerance }
            guard Double(regularGaps.count) / Double(gaps.count) >= 0.6 else { return nil }

            let total = group.reduce(Decimal(0)) { $0 + $1.amount }
            let average = total / Decimal(group.count)

            let displayName = Self.mostCommonMerchant(in: group)

            return Detected(
                merchantKey: key,
                displayName: displayName,
                averageAmount: average,
                cadence: cadence,
                lastOccurrence: sorted.last?.date ?? .now,
                occurrenceCount: group.count
            )
        }
    }

    static func normalizeMerchant(_ merchant: String) -> String {
        let lowered = merchant.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let cleaned = String(scalars)
        // Drop purely-numeric tokens (reference numbers, store ids, dates) that vary per charge.
        let tokens = cleaned.split(separator: " ").filter { !$0.allSatisfy(\.isNumber) }
        let joined = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? lowered.trimmingCharacters(in: .whitespaces) : joined
    }

    private static func mostCommonMerchant(in group: [Transaction]) -> String {
        var counts: [String: Int] = [:]
        for transaction in group {
            counts[transaction.merchant, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key ?? group.first?.merchant ?? "Recurring"
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
