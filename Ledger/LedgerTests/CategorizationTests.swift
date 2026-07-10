import Foundation
import Testing
@testable import Ledger

struct MerchantNormalizationTests {
    @Test func stripsStoreNumbersAndPunctuation() {
        #expect(RecurringDetectionService.normalizeMerchant("SQ *BLUE BOTTLE #123") == "sq blue bottle")
        #expect(RecurringDetectionService.normalizeMerchant("SQ *BLUE BOTTLE #987") == "sq blue bottle")
        #expect(RecurringDetectionService.normalizeMerchant("NETFLIX.COM 4029357733") == "netflix com")
    }

    @Test func fallsBackWhenEverythingIsNumeric() {
        #expect(RecurringDetectionService.normalizeMerchant("12345") == "12345")
    }
}

struct CategorizationMatchingTests {
    @Test func shortKeywordsRequireWholeTokens() {
        // "esso" must not fire inside "espresso", "gym" not inside "gymboree".
        #expect(CategorizationService.matches(keyword: "esso", normalizedMerchant: "esso station"))
        #expect(!CategorizationService.matches(keyword: "esso", normalizedMerchant: "espresso bar"))
        #expect(!CategorizationService.matches(keyword: "gym", normalizedMerchant: "gymboree kids"))
        #expect(CategorizationService.matches(keyword: "gym", normalizedMerchant: "city gym"))
    }

    @Test func longKeywordsMayMatchAsTokenPrefix() {
        #expect(CategorizationService.matches(keyword: "mcdonald", normalizedMerchant: "mcdonalds toronto"))
        #expect(CategorizationService.matches(keyword: "chiropract", normalizedMerchant: "main st chiropractor"))
        // But never mid-token.
        #expect(!CategorizationService.matches(keyword: "rental", normalizedMerchant: "acarrental co"))
    }

    @Test func multiWordKeywordsMatchAtBoundaries() {
        #expect(CategorizationService.matches(keyword: "uber eats", normalizedMerchant: "uber eats toronto"))
        #expect(CategorizationService.matches(keyword: "uber", normalizedMerchant: "uber eats toronto"))
        #expect(!CategorizationService.matches(keyword: "uber eats", normalizedMerchant: "uber trip help"))
    }
}

struct RecurrenceCadenceTests {
    @Test func classifiesMedianGaps() {
        #expect(RecurrenceCadence.classify(medianGapDays: 7) == .weekly)
        #expect(RecurrenceCadence.classify(medianGapDays: 14) == .biweekly)
        #expect(RecurrenceCadence.classify(medianGapDays: 30) == .monthly)
        #expect(RecurrenceCadence.classify(medianGapDays: 91) == .quarterly)
        #expect(RecurrenceCadence.classify(medianGapDays: 365) == .yearly)
        #expect(RecurrenceCadence.classify(medianGapDays: 3) == nil)
        #expect(RecurrenceCadence.classify(medianGapDays: 50) == nil)
    }

    @Test func advancesDatesByCadence() {
        let calendar = Calendar(identifier: .gregorian)
        let jan15 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let next = RecurrenceCadence.monthly.nextDate(after: jan15, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: next)
        #expect(parts.month == 2 && parts.day == 15)
    }
}
