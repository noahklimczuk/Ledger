import SwiftUI
import Foundation

// The redesign's shared building blocks. Screens compose these — icon badges, chips, count-up
// numbers, bold section headers, stat tiles, progress bars, and the primary button — so every area
// looks and moves the same way while carrying its own section accent.

// MARK: - Numbers

/// A number that rolls to its value under animation, so figures count into place instead of snapping.
/// `View` + `Animatable`: SwiftUI interpolates `value` each frame and re-renders the formatted text.
struct CountingNumber: View, Animatable {
    var value: Double
    // @MainActor so the formatter closure can call the main-actor CurrencyFormatter without a
    // concurrency diagnostic; the body that invokes it is main-actor anyway.
    var format: @MainActor (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// A currency figure that counts up from zero when it first appears (and animates to any later value).
struct CountingCurrency: View {
    let value: Decimal
    var currencyCode: String = "CAD"
    @State private var display: Double = 0

    private var target: Double { (value as NSDecimalNumber).doubleValue }

    var body: some View {
        CountingNumber(value: display) { amount in
            CurrencyFormatter.string(from: Decimal(amount), currencyCode: currencyCode)
        }
        .onAppear { withAnimation(Motion.count) { display = target } }
        .onChange(of: value) { _, _ in withAnimation(Motion.count) { display = target } }
    }
}

// MARK: - Icon badge

/// A rounded-square icon chip. `filled` paints it with the accent gradient (white glyph); otherwise a
/// soft tint with a colored glyph. The single most-repeated element in the redesign — every row,
/// header, and tile leads with one.
struct IconBadge: View {
    let systemName: String
    var accent: Accent = .dashboard
    var size: CGFloat = 40
    var filled: Bool = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(accent.base))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(filled ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.soft))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// A small tinted pill for badges/labels — price changes, counts, statuses.
struct Chip: View {
    let text: String
    var systemName: String? = nil
    var color: Color = Palette.indigo

    var body: some View {
        HStack(spacing: 4) {
            if let systemName {
                Image(systemName: systemName).font(.system(size: 10, weight: .black))
            }
            Text(text).font(.appCaption2.weight(.bold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Section header

/// A bold, editorial section header: a heavy title (optionally with a subtitle) and an optional
/// trailing accessory. Sets the confident, big-type tone the redesign is going for.
struct SectionHeadline<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.appTitle3.weight(.heavy))
                if let subtitle {
                    Text(subtitle).font(.appFootnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeadline where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Stat tile

/// A compact tile — leading glyph, a big value, a caption — tinted with an accent. Used in rows of
/// two or three for income/expense/net style summaries.
struct StatTile: View {
    let label: String
    let value: String
    var accent: Accent = .dashboard
    var systemName: String?
    var valueColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemName {
                IconBadge(systemName: systemName, accent: accent, size: 30, filled: false)
            }
            Text(value)
                .font(.appTitle3.weight(.heavy))
                .foregroundStyle(valueColor ?? .primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.soft, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

// MARK: - Progress bar

/// A rounded progress bar in the accent gradient, with an optional overflow color for "over" states.
/// Animate it by changing `fraction` inside a `withAnimation` (or an enclosing `.animation`).
struct AccentProgressBar: View {
    let fraction: Double
    var accent: Accent = .dashboard
    var height: CGFloat = 12
    var overflowColor: Color?

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            let isOver = fraction > 1
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(isOver && overflowColor != nil ? AnyShapeStyle(overflowColor!) : AnyShapeStyle(accent.gradient))
                    .frame(width: max(proxy.size.width * clamped, height))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Primary button

/// The prominent call-to-action: a full-width accent-gradient button with a soft colored shadow and
/// the standard springy press feel.
struct AccentButton: View {
    let title: String
    var systemName: String?
    var accent: Accent = .dashboard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemName { Image(systemName: systemName).font(.appHeadline) }
                Text(title).font(.appHeadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(accent.gradient, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .shadow(color: accent.base.opacity(0.45), radius: 14, y: 8)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Surfaces

extension View {
    /// A soft accent wash behind a screen — a faint tint at the top melting into the app background —
    /// so each area quietly carries its signature color. Pair with `.scrollContentBackground(.hidden)`
    /// on List-based screens so it shows through.
    func accentWash(_ accent: Accent) -> some View {
        background(
            ZStack {
                Color.appBackground
                LinearGradient(
                    colors: [accent.base.opacity(0.18), accent.base.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        )
    }

    /// A tappable card: the standard card surface plus the springy press feel. Wrap the whole card in
    /// a Button and give the label this modifier, or use it on a NavigationLink label.
    func pressableCard(padding: CGFloat = Theme.cardPadding) -> some View {
        card(padding: padding)
    }
}
