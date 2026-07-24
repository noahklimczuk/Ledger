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
            .font(AppFont.scaled(size * 0.42, relativeTo: .body, weight: .bold))
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
                Image(systemName: systemName).font(AppFont.scaled(10, relativeTo: .caption2, weight: .black))
            }
            Text(text).font(.appCaption2.weight(.bold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.22), in: Capsule())
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
            .background(accent.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.bloomShadow, radius: 16, x: 6, y: 6)
            .shadow(color: Color.bloomHighlight, radius: 10, x: -3, y: -3)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Surfaces

extension View {
    /// The Bloom screen background: the warm `--page` base plus two radial glows (top-trailing
    /// amber/peach, bottom-leading green) from `bloom-mobile.html`. Clay cards sit on top so the
    /// depth comes from the cards, not the background.
    func accentWash(_ accent: Accent) -> some View {
        _ = accent
        return background(BloomBackground(), ignoresSafeAreaEdges: .all)
    }

    /// A tappable card: the standard card surface plus the springy press feel. Wrap the whole card in
    /// a Button and give the label this modifier, or use it on a NavigationLink label.
    func pressableCard(padding: CGFloat = Theme.cardPadding) -> some View {
        card(padding: padding)
    }
}

// MARK: - Wellness ring

/// A circular 0–100 gauge for the Financial Wellness score — Bloom's signature widget. The arc fills
/// in the accent gradient with the score (and an optional "/ 100") in the centre, and animates when
/// the score changes. Used large on the Wellness screen and small on the dashboard tile.
struct WellnessRing: View {
    let score: Int
    var accent: Accent = .wellness
    var size: CGFloat = 132
    var lineWidth: CGFloat = 12
    var showLabel: Bool = true

    var body: some View {
        let fraction = min(max(Double(score) / 100, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(accent.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showLabel {
                VStack(spacing: 1) {
                    Text("\(score)")
                        .font(AppFont.scaled(size * 0.34, relativeTo: .largeTitle, weight: .heavy))
                        .foregroundStyle(accent.deep)
                        .minimumScaleFactor(0.6)
                    Text("/ 100")
                        .font(AppFont.scaled(size * 0.09, relativeTo: .caption2, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.smooth, value: score)
        .accessibilityElement()
        .accessibilityLabel("Financial wellness score")
        .accessibilityValue("\(score) out of 100")
    }
}

// MARK: - Balance blob

/// The dashboard's soft "clay" budget blob — a warm peach→amber squircle showing how much of the
/// month's budget is used, sitting beside the balance. Bloom's most recognizable hero element.
struct BalanceBlob: View {
    let percent: Int
    var size: CGFloat = 104

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.46, style: .continuous)
                .fill(LinearGradient(colors: [Palette.peach, Palette.amber], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.46, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Palette.peach.opacity(0.5), radius: 16, y: 10)
            VStack(spacing: 2) {
                Text("\(percent)%")
                    .font(AppFont.scaled(size * 0.22, relativeTo: .largeTitle, weight: .heavy))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                Text("OF BUDGET")
                    .font(AppFont.scaled(size * 0.082, relativeTo: .caption2, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Budget used")
        .accessibilityValue("\(percent) percent")
    }
}

// MARK: - Clay channel (budget bar)

/// A budget bar in Bloom's clay style: a debossed track with a rounded gradient fill, red when over.
/// Used for the dashboard's per-category budget list.
struct ClayChannel: View {
    let progress: Double
    var isOver: Bool = false
    var fillAccent: Accent = .dashboard
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(isOver
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.peach, Palette.coral], startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(fillAccent.gradient))
                    .frame(width: max(geo.size.width * clamped, clamped > 0 ? height : 0))
                    .padding(.vertical, 2)
            }
        }
        .frame(height: height)
        .animation(Motion.snappy, value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Burn-rate meter

/// A cool→hot heat bar with a "you are here" marker — Ember's spending-pace idea, in Bloom. The
/// marker slides toward the hot end as the month's projected spend runs past plan.
struct BurnMeter: View {
    let position: Double
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let x = min(max(position, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [Palette.emerald.opacity(0.55), Palette.amber, Palette.peach, Palette.coral],
                        startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: 4, height: height + 8)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .offset(x: geo.size.width * x - 2)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
