import Foundation

/// RFC 4180-style CSV parser: handles quoted fields, escaped quotes (""), commas and
/// newlines inside quotes, and both LF and CRLF line endings. Returns rows of string
/// cells with the header row (if any) still included -- the caller decides whether row 0
/// is a header.
enum CSVParser {
    static func parse(_ rawText: String) -> [[String]] {
        // Strip a leading UTF-8 BOM if present.
        var text = rawText
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var field = ""
        var inQuotes = false

        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if inQuotes {
                if character == "\"" {
                    let isEscapedQuote = index + 1 < characters.count && characters[index + 1] == "\""
                    if isEscapedQuote {
                        field.append("\"")
                        index += 2
                    } else {
                        inQuotes = false
                        index += 1
                    }
                } else {
                    field.append(character)
                    index += 1
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                currentRow.append(field)
                field = ""
                index += 1
            case "\r":
                if index + 1 < characters.count && characters[index + 1] == "\n" {
                    index += 1
                }
                currentRow.append(field)
                rows.append(currentRow)
                field = ""
                currentRow = []
                index += 1
            case "\n":
                currentRow.append(field)
                rows.append(currentRow)
                field = ""
                currentRow = []
                index += 1
            default:
                field.append(character)
                index += 1
            }
        }

        if !field.isEmpty || !currentRow.isEmpty {
            currentRow.append(field)
            rows.append(currentRow)
        }

        // Drop fully blank rows (a single empty cell) that trailing newlines produce.
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}
