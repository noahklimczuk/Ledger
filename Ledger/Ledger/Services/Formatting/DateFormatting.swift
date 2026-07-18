import Foundation

enum DateFormatting {
    static func short(_ date: Date) -> String {
        styledFormatter(dateStyle: .short).string(from: date)
    }

    static func medium(_ date: Date) -> String {
        styledFormatter(dateStyle: .medium).string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        if let cached = monthYearFormatter { return cached.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        monthYearFormatter = formatter
        return formatter.string(from: date)
    }

    /// "Today" / "Yesterday" for recent dates, otherwise a medium-style date.
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return medium(date)
    }

    /// Forward-looking counterpart to `relativeDay` for scheduled/upcoming dates: "Today",
    /// "Tomorrow", "in N days" within the coming week, otherwise a medium-style date.
    static func relativeUpcoming(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 1 && days <= 7 { return "in \(days) days" }
        return medium(date)
    }

    // DateFormatter construction is expensive and these run for every date label in every list
    // row (and for every unreviewed row in the check-in). Building a fresh formatter each call
    // was a real source of scroll lag, so cache one per style. The module defaults to MainActor
    // isolation, which is what makes the shared cache safe.
    private static var styledFormatters: [DateFormatter.Style: DateFormatter] = [:]
    private static var monthYearFormatter: DateFormatter?

    private static func styledFormatter(dateStyle: DateFormatter.Style) -> DateFormatter {
        if let cached = styledFormatters[dateStyle] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        styledFormatters[dateStyle] = formatter
        return formatter
    }
}
