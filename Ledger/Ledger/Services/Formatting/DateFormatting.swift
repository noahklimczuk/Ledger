import Foundation

enum DateFormatting {
    static func short(_ date: Date) -> String {
        styledFormatter(dateStyle: .short).string(from: date)
    }

    static func medium(_ date: Date) -> String {
        styledFormatter(dateStyle: .medium).string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    /// "Today" / "Yesterday" for recent dates, otherwise a medium-style date.
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return medium(date)
    }

    private static func styledFormatter(dateStyle: DateFormatter.Style) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        return formatter
    }
}
