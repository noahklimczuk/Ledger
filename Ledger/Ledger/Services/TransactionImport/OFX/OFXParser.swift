import Foundation

/// A single transaction pulled from an OFX/QFX statement.
struct OFXRecord: Sendable {
    let fitid: String
    let date: Date
    let merchant: String
    let amount: Decimal
}

/// Minimal OFX/QFX parser. OFX is SGML-ish and often omits closing tags, so rather than a
/// full XML parse this scans each `<STMTTRN>` block and reads the value that follows a tag up
/// to the next tag or line break. Good enough for the statement downloads banks (incl.
/// Wealthsimple's OFX export) produce; FITID gives us a stable id for dedup.
enum OFXParser {
    static func parse(_ text: String) -> [OFXRecord] {
        let blocks = text.components(separatedBy: "<STMTTRN>").dropFirst()

        return blocks.compactMap { block -> OFXRecord? in
            guard let fitid = value(of: "FITID", in: block),
                  let rawDate = value(of: "DTPOSTED", in: block),
                  let rawAmount = value(of: "TRNAMT", in: block),
                  let amount = ImportValueParsing.decimal(from: rawAmount),
                  let date = parseOFXDate(rawDate) else {
                return nil
            }

            let name = value(of: "NAME", in: block)
            let memo = value(of: "MEMO", in: block)
            let merchant = [name, memo].compactMap { $0 }.first { !$0.isEmpty } ?? "Imported transaction"

            return OFXRecord(fitid: fitid, date: date, merchant: merchant, amount: amount)
        }
    }

    /// Reads the text after `<TAG>` up to the next `<` or newline.
    private static func value(of tag: String, in block: String) -> String? {
        guard let range = block.range(of: "<\(tag)>") else { return nil }
        let remainder = block[range.upperBound...]
        let terminators = CharacterSet(charactersIn: "<\r\n")
        let end = remainder.unicodeScalars.firstIndex { terminators.contains($0) } ?? remainder.unicodeScalars.endIndex
        let value = String(remainder.unicodeScalars[remainder.unicodeScalars.startIndex..<end])
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// OFX dates look like `20240115` or `20240115120000.000[-5:EST]`; the first 8 digits are yyyyMMdd.
    private static func parseOFXDate(_ raw: String) -> Date? {
        let digits = raw.prefix { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        return ImportValueParsing.date(from: String(digits.prefix(8)), preferredFormat: "yyyyMMdd")
    }
}
