import Foundation

/// The built-in set of common budgeting categories and the merchant keywords that map onto them.
/// Seeded by `DefaultDataSeeder` so a brand-new install already has sensible categories to budget
/// against and rules to auto-categorize transactions with. The user can still add, rename, or
/// delete categories freely — this is only the starting point.
///
/// Keyword ground rules (they're matched by `CategorizationService` with token-boundary rules):
/// - Keywords under 5 characters must match a whole token, so short brands ("kfc", "saq", "iga")
///   are safe to list without firing inside longer words.
/// - Longer keywords may match as a token prefix — "mcdonald" covers "mcdonalds", "chiropract"
///   covers "chiropractor" and "chiropractic".
/// - When two keywords both match, the longest wins ("uber eats" beats "uber", "costco gas"
///   beats "costco", "interest charge" beats "interest").
enum DefaultCategoryCatalog {
    struct CategorySeed {
        let name: String
        let symbol: String
        let colorHex: String
        let isIncome: Bool
        /// Merchant keywords that should auto-map to this category (normalized at seed time).
        let keywords: [String]
        /// Seed-catalog version that introduced this category. Lets `DefaultDataSeeder` add new
        /// categories to existing installs without resurrecting older ones the user deleted.
        var introducedInVersion: Int = 1
    }

    /// Bump when adding categories or keywords so existing installs pick the additions up.
    static let version = 2

    /// Ordered so `sortOrder` reflects a natural grouping (income first, then essentials, then
    /// discretionary). Colors are drawn from the system palette for good light/dark contrast.
    static let categories: [CategorySeed] = [
        // Income
        CategorySeed(name: "Salary", symbol: "dollarsign.circle.fill", colorHex: "#34C759", isIncome: true,
                     keywords: ["payroll", "salary", "direct deposit", "paycheque", "paycheck", "employer"]),
        CategorySeed(name: "Interest", symbol: "percent", colorHex: "#30D158", isIncome: true,
                     keywords: ["interest"]),
        CategorySeed(name: "Refunds", symbol: "arrow.uturn.left.circle.fill", colorHex: "#32ADE6", isIncome: true,
                     keywords: ["refund", "reimbursement", "cra", "tax refund", "gst", "rebate", "cashback",
                                "cash back"]),
        CategorySeed(name: "Other Income", symbol: "plus.circle.fill", colorHex: "#64D2FF", isIncome: true,
                     keywords: []),

        // Essentials
        CategorySeed(name: "Groceries", symbol: "cart.fill", colorHex: "#30B0C7", isIncome: false,
                     keywords: ["grocery", "loblaws", "metro", "sobeys", "no frills", "food basics",
                                "costco", "walmart", "superstore", "whole foods", "safeway", "farm boy",
                                "freshco", "save on foods", "longos", "supermarket", "iga", "giant tiger",
                                "provigo", "maxi", "bulk barn", "foodland", "fortinos", "zehrs",
                                "valu mart", "independent grocer"]),
        CategorySeed(name: "Restaurants", symbol: "fork.knife", colorHex: "#FF9500", isIncome: false,
                     keywords: ["restaurant", "mcdonald", "burger", "pizza", "sushi", "uber eats",
                                "doordash", "skipthedishes", "wendys", "subway", "chipotle",
                                "kfc", "taco bell", "dominos", "swiss chalet", "diner", "harveys",
                                "popeyes", "five guys", "boston pizza", "the keg", "a w", "freshii",
                                "shawarma", "pho", "ramen", "poutine", "grill", "bistro", "eatery"]),
        CategorySeed(name: "Coffee", symbol: "cup.and.saucer.fill", colorHex: "#A2845E", isIncome: false,
                     keywords: ["starbucks", "tim hortons", "coffee", "second cup", "mccafe", "espresso",
                                "cafe", "caffe", "dunkin"]),
        CategorySeed(name: "Gas", symbol: "fuelpump.fill", colorHex: "#FF3B30", isIncome: false,
                     keywords: ["shell", "esso", "petro canada", "petrocanada", "chevron", "husky",
                                "ultramar", "fuelpump", "gas station", "petro", "circle k", "pioneer",
                                "mobil", "irving", "sunoco", "costco gas", "canco", "fas gas"]),
        CategorySeed(name: "Transit", symbol: "tram.fill", colorHex: "#5856D6", isIncome: false,
                     keywords: ["transit", "presto", "go transit", "ttc", "metro pass", "parking",
                                "via rail", "oc transpo", "stm", "translink", "bixi", "impark",
                                "green p"]),
        CategorySeed(name: "Rideshare", symbol: "car.fill", colorHex: "#5E5CE6", isIncome: false,
                     keywords: ["uber", "lyft"]),
        CategorySeed(name: "Rent", symbol: "house.fill", colorHex: "#BF5AF2", isIncome: false,
                     keywords: ["rent", "landlord", "property management", "apartment"]),
        CategorySeed(name: "Utilities", symbol: "bolt.fill", colorHex: "#FFCC00", isIncome: false,
                     keywords: ["hydro", "utility", "utilities", "enbridge", "gas company", "electric",
                                "epcor", "fortis", "enmax", "atco"]),
        CategorySeed(name: "Phone & Internet", symbol: "wifi", colorHex: "#0A84FF", isIncome: false,
                     keywords: ["rogers", "bell canada", "bell mobility", "telus", "fido", "koodo",
                                "freedom mobile", "virgin mobile", "virgin plus", "shaw", "videotron",
                                "internet", "wireless", "chatr", "public mobile", "lucky mobile",
                                "cogeco", "eastlink", "teksavvy", "xplornet", "sasktel"]),
        CategorySeed(name: "Insurance", symbol: "checkmark.shield.fill", colorHex: "#64D2FF", isIncome: false,
                     keywords: ["insurance", "intact", "aviva", "sun life", "manulife", "belairdirect",
                                "td insurance", "wawanesa", "allstate", "canada life", "blue cross",
                                "desjardins insurance", "co operators"]),
        CategorySeed(name: "Health", symbol: "cross.case.fill", colorHex: "#FF375F", isIncome: false,
                     keywords: ["pharmacy", "shoppers drug", "rexall", "dental", "clinic", "doctor",
                                "medical", "optometry", "physio", "dentist", "chiropract", "massage",
                                "jean coutu", "familiprix", "london drugs", "optical"]),

        // Discretionary
        CategorySeed(name: "Subscriptions", symbol: "repeat.circle.fill", colorHex: "#FF2D55", isIncome: false,
                     keywords: ["netflix", "spotify", "disney", "crave", "amazon prime", "apple com bill",
                                "icloud", "youtube premium", "patreon", "audible", "hbo", "paramount",
                                "apple music", "apple tv", "apple one", "google one", "google storage",
                                "youtube", "twitch", "substack", "dropbox", "adobe", "microsoft",
                                "openai", "chatgpt", "canva", "prime video"]),
        CategorySeed(name: "Shopping", symbol: "bag.fill", colorHex: "#FF9F0A", isIncome: false,
                     keywords: ["amazon", "amzn", "best buy", "the bay", "winners", "ikea", "canadian tire",
                                "home depot", "indigo", "sephora", "lululemon", "aritzia", "dollarama",
                                "dollar tree", "simons", "uniqlo", "zara", "h m", "old navy", "marshalls",
                                "homesense", "structube", "wayfair", "etsy", "ebay", "aliexpress",
                                "temu", "shein", "staples", "apple store", "sport chek", "marks"]),
        CategorySeed(name: "Entertainment", symbol: "film.fill", colorHex: "#BF5AF2", isIncome: false,
                     keywords: ["cineplex", "movie", "theatre", "steam", "playstation", "xbox", "nintendo",
                                "concert", "ticketmaster", "cinema", "landmark", "imax", "stubhub",
                                "eventbrite", "bowling", "arcade", "casino"]),
        CategorySeed(name: "Fitness", symbol: "figure.run", colorHex: "#30D158", isIncome: false,
                     keywords: ["gym", "goodlife", "fitness", "yoga", "peloton", "planet fitness",
                                "orangetheory", "crossfit", "climbing", "ymca", "recreation"]),
        CategorySeed(name: "Travel", symbol: "airplane", colorHex: "#5AC8FA", isIncome: false,
                     keywords: ["air canada", "westjet", "airline", "hotel", "airbnb", "expedia", "booking com",
                                "flight", "porter", "flair", "sunwing", "transat", "vrbo", "hostel",
                                "marriott", "hilton", "hertz", "avis", "enterprise rent", "budget rent"]),
        CategorySeed(name: "Fees", symbol: "creditcard.trianglebadge.exclamationmark", colorHex: "#8E8E93", isIncome: false,
                     keywords: ["nsf", "overdraft", "service charge", "monthly fee", "interest charge",
                                "atm fee", "annual fee", "late fee", "bank fee", "fee", "fees"]),

        // Introduced in catalog version 2
        CategorySeed(name: "Alcohol & Bars", symbol: "wineglass.fill", colorHex: "#AF52DE", isIncome: false,
                     keywords: ["lcbo", "beer store", "saq", "liquor", "brewery", "brewing", "winery",
                                "wine rack", "craft beer", "taproom"],
                     introducedInVersion: 2),
        CategorySeed(name: "Personal Care", symbol: "scissors", colorHex: "#FF6482", isIncome: false,
                     keywords: ["salon", "barber", "spa", "nails", "esthetic", "cosmetic", "hair",
                                "waxing", "dry cleaning"],
                     introducedInVersion: 2),
        CategorySeed(name: "Home", symbol: "wrench.and.screwdriver.fill", colorHex: "#AC8E68", isIncome: false,
                     keywords: ["rona", "lowes", "home hardware", "handyman", "plumber", "plumbing",
                                "electrician", "pest control", "cleaning", "lawn", "landscap"],
                     introducedInVersion: 2),
        CategorySeed(name: "Pets", symbol: "pawprint.fill", colorHex: "#FF7A45", isIncome: false,
                     keywords: ["petsmart", "pet valu", "petco", "veterinary", "vet clinic", "petland",
                                "pet store", "global pet"],
                     introducedInVersion: 2),
        CategorySeed(name: "Education", symbol: "graduationcap.fill", colorHex: "#7D7AFF", isIncome: false,
                     keywords: ["tuition", "university", "college", "udemy", "coursera", "skillshare",
                                "textbook", "school", "duolingo"],
                     introducedInVersion: 2),
        CategorySeed(name: "Gifts & Donations", symbol: "gift.fill", colorHex: "#E64980", isIncome: false,
                     keywords: ["donation", "charity", "gofundme", "red cross", "unicef",
                                "salvation army", "gift"],
                     introducedInVersion: 2),
        CategorySeed(name: "Transfers", symbol: "arrow.left.arrow.right.circle.fill", colorHex: "#98989D", isIncome: false,
                     keywords: ["e transfer", "etransfer", "interac e transfer", "transfer",
                                "wealthsimple", "questrade", "wise"],
                     introducedInVersion: 2),

        CategorySeed(name: "Other", symbol: "square.grid.2x2.fill", colorHex: "#8E8E93", isIncome: false,
                     keywords: []),
    ]
}
