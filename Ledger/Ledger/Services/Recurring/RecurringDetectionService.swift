import Foundation
import SwiftData

/// Detects recurring charges/income from transaction history and reconciles them into the stored
/// `RecurringSeries` set. Signal is regularity of spacing: a merchant whose transactions land at a
/// consistent cadence (weekly/biweekly/monthly/quarterly/yearly) with ≥3 occurrences is a candidate.
/// Each candidate gets a 0…1 confidence from three parts — how regular the gaps are, how stable the
/// amount is, and how much history backs it — so weak guesses become `.suggested` (needing review)
/// while strong ones go straight to `.active`.
///
/// Explicitly `nonisolated` — it only touches its `ModelContext` and pure date/amount logic, so it
/// runs on whatever executor its context belongs to (the main context from views, or a background
/// context during the off-main auto-sync). The project defaults types to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), so this opt-out is what actually lets `TransactionSyncActor`
/// use it off the main thread; `@MainActor` callers can still use it inline.
nonisolated final class RecurringDetectionService {
    private let modelContext: ModelContext

    /// Minimum occurrences to establish a cadence (needs ≥2 gaps).
    private let minimumOccurrences = 3
    /// Fraction of gaps that must sit near the cadence for a merchant to be admitted at all.
    private let minimumRegularity = 0.5
    /// Confidence at/above which a fresh detection is trusted as `.active`; below it is `.suggested`.
    private let autoActiveConfidence = 0.72

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    struct Detected {
        let merchantKey: String
        let displayName: String
        let averageAmount: Decimal
        /// Most recent occurrence's amount, and the typical amount before it — for price-change checks.
        let lastAmount: Decimal
        let baselineAmount: Decimal
        let cadence: RecurrenceCadence
        let firstOccurrence: Date
        let lastOccurrence: Date
        let occurrenceCount: Int
        /// 0…1 overall confidence this is a genuine recurring series.
        let confidence: Double
    }

    /// Re-runs detection and upserts results, preserving the user's review choices. New high-confidence
    /// detections become `.active`, weaker ones `.suggested`; an active series whose next charge is
    /// well overdue is auto-marked `.ended` (likely cancelled). User `paused`/`ignored` states are
    /// never overwritten. Series that lose all support (and weren't user-kept) are removed.
    func refresh(now: Date = .now) {
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
                // Capture whether this run actually saw a newer charge than we had before, so a
                // user-ended series isn't revived just because it happens not to be overdue.
                let hadNewCharge = item.lastOccurrence > series.lastOccurrence
                series.displayName = item.displayName
                series.averageAmount = item.averageAmount
                series.lastAmount = item.lastAmount
                series.baselineAmount = item.baselineAmount
                series.cadence = item.cadence
                series.firstOccurrence = item.firstOccurrence
                series.lastOccurrence = item.lastOccurrence
                series.nextExpected = nextExpected
                series.occurrenceCount = item.occurrenceCount
                series.detectionConfidence = item.confidence
                series.updatedAt = .now
                series.statusRaw = reconciledStatus(for: series, nextExpected: nextExpected, now: now, hadNewCharge: hadNewCharge).rawValue
            } else {
                let status: RecurringStatus = item.confidence >= autoActiveConfidence ? .active : .suggested
                let series = RecurringSeries(
                    merchantKey: item.merchantKey,
                    displayName: item.displayName,
                    averageAmount: item.averageAmount,
                    cadence: item.cadence,
                    lastOccurrence: item.lastOccurrence,
                    nextExpected: nextExpected,
                    occurrenceCount: item.occurrenceCount,
                    statusRaw: status.rawValue,
                    detectionConfidence: item.confidence,
                    firstOccurrence: item.firstOccurrence,
                    lastAmount: item.lastAmount,
                    baselineAmount: item.baselineAmount
                )
                // A brand-new detection that's already well overdue is surfaced as ended, not active.
                series.statusRaw = overdueEnds(series, nextExpected: nextExpected, now: now) ? RecurringStatus.ended.rawValue : status.rawValue
                modelContext.insert(series)
            }
        }

        // Drop series that lost all detection support, unless the user is holding onto them
        // (ignored/paused) or they're a still-meaningful ended record.
        for series in existing where !detectedKeys.contains(series.merchantKey) {
            let userKept = series.isIgnored || series.statusRaw == RecurringStatus.paused.rawValue
            if !userKept { modelContext.delete(series) }
        }

        try? modelContext.save()
    }

    /// Chooses the lifecycle state for an existing series after refresh, honoring user intent:
    /// ignored/paused/suggested are left as the user (or a prior run) set them. A live series is kept
    /// active unless its next charge is well overdue (then it's ended — likely cancelled). An ended
    /// series stays ended until a genuinely newer charge lands, so a manual "Mark as Ended" (or an
    /// auto-end) doesn't flip back the instant the series isn't technically overdue.
    private func reconciledStatus(for series: RecurringSeries, nextExpected: Date, now: Date, hadNewCharge: Bool) -> RecurringStatus {
        if series.isIgnored { return .ignored }
        switch RecurringStatus(rawValue: series.statusRaw) ?? .active {
        case .ignored: return .ignored
        case .paused: return .paused
        case .suggested: return .suggested
        case .active:
            return overdueEnds(series, nextExpected: nextExpected, now: now) ? .ended : .active
        case .ended:
            return (hadNewCharge && !overdueEnds(series, nextExpected: nextExpected, now: now)) ? .active : .ended
        }
    }

    /// True when the next expected charge is overdue by more than half a cadence plus a few days'
    /// grace — enough to call a subscription "likely cancelled" without flapping on a late charge.
    private func overdueEnds(_ series: RecurringSeries, nextExpected: Date, now: Date) -> Bool {
        let grace = Double(series.cadence.approximateDays) * 0.5 + 5
        let overdueDays = now.timeIntervalSince(nextExpected) / 86_400
        return overdueDays > grace
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

            // Most gaps must sit near the cadence, or it's an irregular merchant, not a subscription.
            let tolerance = Double(cadence.approximateDays) * 0.4
            let regularCount = gaps.filter { abs($0 - Double(cadence.approximateDays)) <= tolerance }.count
            let regularity = Double(regularCount) / Double(gaps.count)
            guard regularity >= minimumRegularity else { return nil }

            let amounts = sorted.map(\.amount)
            let total = amounts.reduce(Decimal(0), +)
            let average = total / Decimal(amounts.count)
            let lastAmount = amounts.last ?? average
            // Baseline = typical amount before the latest charge, so a fresh price change stands out.
            let baseline = Self.median(amounts.dropLast().map { ($0 as NSDecimalNumber).doubleValue })
                .map { Decimal($0) } ?? average

            let confidence = Self.confidence(
                regularity: regularity,
                amounts: amounts,
                occurrenceCount: group.count
            )

            return Detected(
                merchantKey: key,
                displayName: Self.mostCommonMerchant(in: group),
                averageAmount: average,
                lastAmount: lastAmount,
                baselineAmount: baseline,
                cadence: cadence,
                firstOccurrence: sorted.first?.date ?? .now,
                lastOccurrence: sorted.last?.date ?? .now,
                occurrenceCount: group.count,
                confidence: confidence
            )
        }
    }

    /// Blends three signals into a 0…1 score: gap regularity (how evenly spaced), amount stability
    /// (how consistent the charge is), and history depth (more occurrences = more trustworthy).
    static func confidence(regularity: Double, amounts: [Decimal], occurrenceCount: Int) -> Double {
        let magnitudes = amounts.map { abs(($0 as NSDecimalNumber).doubleValue) }
        let mean = magnitudes.reduce(0, +) / Double(max(magnitudes.count, 1))
        let amountStability: Double
        if mean <= 0 {
            amountStability = 0
        } else {
            let variance = magnitudes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(magnitudes.count)
            let coefficientOfVariation = variance.squareRoot() / mean
            amountStability = max(0, 1 - min(1, coefficientOfVariation))
        }
        let depth = min(1, Double(occurrenceCount) / 6)
        let score = 0.5 * regularity + 0.3 * amountStability + 0.2 * depth
        return min(1, max(0, score))
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
