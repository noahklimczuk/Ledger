import Foundation

/// The built-in set of common budgeting categories and the merchant keywords that map onto them.
/// Seeded once on first launch (`DefaultDataSeeder`) so a brand-new install already has sensible
/// categories to budget against and rules to auto-categorize transactions with. The user can still
/// add, rename, or delete categories freely — this is only the starting point.
enum DefaultCategoryCatalog {
    struct CategorySeed {
        let name: String
        let symbol: String
        let colorHex: String
        let isIncome: Bool
        /// Normalized merchant keywords that should auto-map to this category.
        let keywords: [String]
    }

    /// Ordered so `sortOrder` reflects a natural grouping (income first, then essentials, then
    /// discretionary). Colors are drawn from the system palette for good light/dark contrast.
    static let categories: [CategorySeed] = [
        // Income
        CategorySeed(name: "Salary", symbol: "dollarsign.circle.fill", colorHex: "#34C759", isIncome: true,
                     keywords: ["payroll", "salary", "direct deposit", "paycheque", "paycheck", "employer"]),
        CategorySeed(name: "Interest", symbol: "percent", colorHex: "#30D158", isIncome: true,
                     keywords: ["interest"]),
        CategorySeed(name: "Refunds", symbol: "arrow.uturn.left.circle.fill", colorHex: "#32ADE6", isIncome: true,
                     keywords: ["refund", "reimbursement"]),
        CategorySeed(name: "Other Income", symbol: "plus.circle.fill", colorHex: "#64D2FF", isIncome: true,
                     keywords: []),

        // Essentials
        CategorySeed(name: "Groceries", symbol: "cart.fill", colorHex: "#30B0C7", isIncome: false,
                     keywords: ["grocery", "loblaws", "metro", "sobeys", "no frills", "food basics",
                                "costco", "walmart", "superstore", "whole foods", "safeway", "farm boy",
                                "freshco", "save on foods", "longos"]),
        CategorySeed(name: "Restaurants", symbol: "fork.knife", colorHex: "#FF9500", isIncome: false,
                     keywords: ["restaurant", "mcdonald", "burger", "pizza", "sushi", "uber eats",
                                "doordash", "skipthedishes", "wendys", "subway", "chipotle",
                                "kfc", "taco bell", "dominos", "swiss chalet", "diner"]),
        CategorySeed(name: "Coffee", symbol: "cup.and.saucer.fill", colorHex: "#A2845E", isIncome: false,
                     keywords: ["starbucks", "tim hortons", "coffee", "second cup", "mccafe", "espresso"]),
        CategorySeed(name: "Gas", symbol: "fuelpump.fill", colorHex: "#FF3B30", isIncome: false,
                     keywords: ["shell", "esso", "petro canada", "petrocanada", "chevron", "husky",
                                "ultramar", "fuelpump", "gas station"]),
        CategorySeed(name: "Transit", symbol: "tram.fill", colorHex: "#5856D6", isIncome: false,
                     keywords: ["transit", "presto", "go transit", "ttc", "metro pass", "parking"]),
        CategorySeed(name: "Rideshare", symbol: "car.fill", colorHex: "#5E5CE6", isIncome: false,
                     keywords: ["uber", "lyft"]),
        CategorySeed(name: "Rent", symbol: "house.fill", colorHex: "#BF5AF2", isIncome: false,
                     keywords: ["rent", "landlord", "property management"]),
        CategorySeed(name: "Utilities", symbol: "bolt.fill", colorHex: "#FFCC00", isIncome: false,
                     keywords: ["hydro", "utility", "enbridge", "gas company", "electric",
                                "epcor", "fortis"]),
        CategorySeed(name: "Phone & Internet", symbol: "wifi", colorHex: "#0A84FF", isIncome: false,
                     keywords: ["rogers", "bell canada", "bell mobility", "telus", "fido", "koodo",
                                "freedom mobile", "virgin mobile", "virgin plus", "shaw", "videotron",
                                "internet", "wireless"]),
        CategorySeed(name: "Insurance", symbol: "checkmark.shield.fill", colorHex: "#64D2FF", isIncome: false,
                     keywords: ["insurance", "intact", "aviva", "sun life", "manulife"]),
        CategorySeed(name: "Health", symbol: "cross.case.fill", colorHex: "#FF375F", isIncome: false,
                     keywords: ["pharmacy", "shoppers drug", "rexall", "dental", "clinic", "doctor",
                                "medical", "optometry", "physio"]),

        // Discretionary
        CategorySeed(name: "Subscriptions", symbol: "repeat.circle.fill", colorHex: "#FF2D55", isIncome: false,
                     keywords: ["netflix", "spotify", "disney", "crave", "amazon prime", "apple com bill",
                                "icloud", "youtube premium", "patreon", "audible", "hbo", "paramount"]),
        CategorySeed(name: "Shopping", symbol: "bag.fill", colorHex: "#FF9F0A", isIncome: false,
                     keywords: ["amazon", "amzn", "best buy", "the bay", "winners", "ikea", "canadian tire",
                                "home depot", "indigo", "sephora", "lululemon", "aritzia"]),
        CategorySeed(name: "Entertainment", symbol: "film.fill", colorHex: "#BF5AF2", isIncome: false,
                     keywords: ["cineplex", "movie", "theatre", "steam", "playstation", "xbox", "nintendo",
                                "concert", "ticketmaster"]),
        CategorySeed(name: "Fitness", symbol: "figure.run", colorHex: "#30D158", isIncome: false,
                     keywords: ["gym", "goodlife", "fitness", "yoga", "peloton", "planet fitness"]),
        CategorySeed(name: "Travel", symbol: "airplane", colorHex: "#5AC8FA", isIncome: false,
                     keywords: ["air canada", "westjet", "airline", "hotel", "airbnb", "expedia", "booking com",
                                "flight", "porter"]),
        CategorySeed(name: "Fees", symbol: "creditcard.trianglebadge.exclamationmark", colorHex: "#8E8E93", isIncome: false,
                     keywords: ["nsf", "overdraft", "service charge", "monthly fee", "interest charge"]),
        CategorySeed(name: "Other", symbol: "square.grid.2x2.fill", colorHex: "#8E8E93", isIncome: false,
                     keywords: []),
    ]
}
