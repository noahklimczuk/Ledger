import Foundation
import Testing
@testable import Ledger

struct ImportValueParsingTests {
    @Test func parsesPlainAmounts() {
        #expect(ImportValueParsing.decimal(from: "12.34") == Decimal(string: "12.34"))
        #expect(ImportValueParsing.decimal(from: "  20.00 ") == Decimal(20))
        #expect(ImportValueParsing.decimal(from: "0") == 0)
    }

    @Test func parsesSignsAndSymbols() {
        #expect(ImportValueParsing.decimal(from: "-12.30") == Decimal(string: "-12.30"))
        #expect(ImportValueParsing.decimal(from: "+5") == Decimal(5))
        #expect(ImportValueParsing.decimal(from: "$1,234.56") == Decimal(string: "1234.56"))
        #expect(ImportValueParsing.decimal(from: "(45.00)") == Decimal(-45))
    }

    @Test func rejectsGarbage() {
        #expect(ImportValueParsing.decimal(from: "") == nil)
        #expect(ImportValueParsing.decimal(from: "   ") == nil)
        #expect(ImportValueParsing.decimal(from: "abc") == nil)
    }

    @Test func parsesCommonDateFormats() {
        let calendar = Calendar(identifier: .gregorian)
        func ymd(_ date: Date?) -> DateComponents? {
            guard let date else { return nil }
            var utc = calendar
            utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.dateComponents([.year, .month, .day], from: date)
        }

        for raw in ["2024-03-15", "2024/03/15", "03/15/2024", "20240315", "Mar 15, 2024"] {
            let parsed = ymd(ImportValueParsing.date(from: raw, preferredFormat: nil))
            #expect(parsed?.year == 2024 && parsed?.month == 3 && parsed?.day == 15, "failed for \(raw)")
        }
        #expect(ImportValueParsing.date(from: "not a date", preferredFormat: nil) == nil)
    }
}

struct CSVParserTests {
    @Test func parsesQuotedFieldsAndEscapes() {
        let rows = CSVParser.parse("a,\"b, with comma\",\"say \"\"hi\"\"\"\nc,d,e\n")
        #expect(rows == [["a", "b, with comma", "say \"hi\""], ["c", "d", "e"]])
    }

    @Test func handlesCRLFAndBOM() {
        let rows = CSVParser.parse("\u{FEFF}h1,h2\r\nv1,v2\r\n")
        #expect(rows == [["h1", "h2"], ["v1", "v2"]])
    }

    @Test func handlesNewlineInsideQuotes() {
        let rows = CSVParser.parse("a,\"line1\nline2\"\n")
        #expect(rows == [["a", "line1\nline2"]])
    }

    @Test func autodetectsSingleAmountLayout() {
        let mapping = CSVColumnMapping.autodetect(headers: ["Date", "Description", "Amount"])
        #expect(mapping.dateColumn == 0)
        #expect(mapping.merchantColumn == 1)
        #expect(mapping.amountMode == .single)
        #expect(mapping.amountColumn == 2)
    }

    @Test func autodetectsSeparateInOutLayout() {
        let mapping = CSVColumnMapping.autodetect(headers: ["Date", "Payee", "Withdrawal", "Deposit"])
        #expect(mapping.amountMode == .separateInOut)
        #expect(mapping.outflowColumn == 2)
        #expect(mapping.inflowColumn == 3)
    }
}

struct OFXParserTests {
    @Test func parsesStatementTransactions() {
        let ofx = """
        <OFX><BANKTRANLIST>
        <STMTTRN>
        <TRNTYPE>DEBIT
        <DTPOSTED>20240115120000.000[-5:EST]
        <TRNAMT>-42.50
        <FITID>abc123
        <NAME>COFFEE SHOP
        </STMTTRN>
        </BANKTRANLIST></OFX>
        """
        let records = OFXParser.parse(ofx)
        #expect(records.count == 1)
        #expect(records.first?.fitid == "abc123")
        #expect(records.first?.amount == Decimal(string: "-42.50"))
        #expect(records.first?.merchant == "COFFEE SHOP")
    }

    @Test func skipsBlocksMissingRequiredFields() {
        let ofx = "<STMTTRN><NAME>NO ID OR AMOUNT</STMTTRN>"
        #expect(OFXParser.parse(ofx).isEmpty)
    }
}
