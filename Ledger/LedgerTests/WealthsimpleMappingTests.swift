import Foundation
import Testing
@testable import Ledger

/// Covers the pure mapping from Wealthsimple's API shapes to Ledger's `ImportedAccount` /
/// `ImportedTransaction`, which is the part that can go wrong without a live account to test
/// against: which accounts we keep, and the amount sign / description of each activity.
struct WealthsimpleMappingTests {

    // MARK: - Accounts

    @Test func keepsOpenCashAccountAndBalance() throws {
        let node = WealthsimpleDTO.AccountNode(
            id: "cash-1",
            unifiedAccountType: "CASH",
            currency: "CAD",
            nickname: "Spending",
            status: "open",
            financials: .init(currentCombined: .init(netLiquidationValue: .init(amount: "1234.56", currency: "CAD")))
        )
        let account = try #require(WealthsimpleTransactionSource.mapAccount(node))
        #expect(account.id == "cash-1")
        #expect(account.name == "Spending")
        #expect(account.type == .chequing)
        #expect(account.currencyCode == "CAD")
        #expect(account.currentBalance == Decimal(string: "1234.56"))
    }

    @Test func fallsBackToDefaultNameWhenNoNickname() throws {
        let node = WealthsimpleDTO.AccountNode(
            id: "cash-2", unifiedAccountType: "CASH", currency: nil, nickname: nil, status: "open", financials: nil
        )
        let account = try #require(WealthsimpleTransactionSource.mapAccount(node))
        #expect(account.name == "Wealthsimple Cash")
        #expect(account.currencyCode == "CAD")
        #expect(account.currentBalance == nil)
    }

    @Test func skipsNonCashAndClosedAccounts() {
        let investment = WealthsimpleDTO.AccountNode(
            id: "tfsa", unifiedAccountType: "SELF_DIRECTED_TFSA", currency: "CAD", nickname: nil, status: "open", financials: nil
        )
        let closedCash = WealthsimpleDTO.AccountNode(
            id: "cash-closed", unifiedAccountType: "CASH", currency: "CAD", nickname: nil, status: "closed", financials: nil
        )
        #expect(WealthsimpleTransactionSource.mapAccount(investment) == nil)
        #expect(WealthsimpleTransactionSource.mapAccount(closedCash) == nil)
    }

    // MARK: - Activities

    @Test func negativeSignMeansMoneyOut() throws {
        let node = activity(amount: "42.50", sign: "negative", type: "SPEND", spendMerchant: "Loblaws")
        let txn = try #require(WealthsimpleTransactionSource.mapActivity(node, accountExternalId: "cash-1"))
        #expect(txn.amount == Decimal(string: "-42.50"))
        #expect(txn.merchant == "Loblaws")
        #expect(txn.id == "act-1")
        #expect(txn.accountExternalId == "cash-1")
    }

    @Test func positiveSignMeansMoneyIn() throws {
        let node = activity(amount: "100", sign: "positive", type: "DEPOSIT", eTransferName: "Jane Doe")
        let txn = try #require(WealthsimpleTransactionSource.mapActivity(node, accountExternalId: "cash-1"))
        #expect(txn.amount == Decimal(100))
        #expect(txn.merchant == "e-Transfer: Jane Doe")
    }

    @Test func skipsRejectedAndLegacyTransfers() {
        let rejected = activity(amount: "10", sign: "negative", type: "SPEND", status: "rejected")
        let legacy = activity(amount: "10", sign: "positive", type: "LEGACY_TRANSFER")
        #expect(WealthsimpleTransactionSource.mapActivity(rejected, accountExternalId: "cash-1") == nil)
        #expect(WealthsimpleTransactionSource.mapActivity(legacy, accountExternalId: "cash-1") == nil)
    }

    @Test func skipsActivityWithNoAmount() {
        let node = activity(amount: nil, sign: "negative", type: "SPEND")
        #expect(WealthsimpleTransactionSource.mapActivity(node, accountExternalId: "cash-1") == nil)
    }

    @Test func describesFromTypeWhenNoLabelFields() throws {
        let node = activity(amount: "5", sign: "negative", type: "INTEREST")
        let txn = try #require(WealthsimpleTransactionSource.mapActivity(node, accountExternalId: "cash-1"))
        #expect(txn.merchant == "Interest")
    }

    @Test func parsesOccurredAtDate() throws {
        let node = activity(amount: "5", sign: "negative", type: "SPEND", occurredAt: "2024-03-15T10:30:00.000Z")
        let txn = try #require(WealthsimpleTransactionSource.mapActivity(node, accountExternalId: "cash-1"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day], from: txn.date)
        #expect(parts.year == 2024 && parts.month == 3 && parts.day == 15)
    }

    // MARK: - Helpers

    private func activity(
        amount: String?,
        sign: String,
        type: String,
        subType: String? = nil,
        status: String? = "settled",
        occurredAt: String? = "2024-03-15T10:30:00.000Z",
        spendMerchant: String? = nil,
        eTransferName: String? = nil
    ) -> WealthsimpleDTO.ActivityNode {
        WealthsimpleDTO.ActivityNode(
            canonicalId: "act-1",
            accountId: "cash-1",
            amount: amount,
            amountSign: sign,
            currency: "CAD",
            occurredAt: occurredAt,
            type: type,
            subType: subType,
            status: status,
            spendMerchant: spendMerchant,
            eTransferName: eTransferName,
            aftOriginatorName: nil,
            billPayCompanyName: nil,
            billPayPayeeNickname: nil,
            p2pHandle: nil
        )
    }
}
