import SwiftUI

enum LiquidPalette {
    static let accent = Color(red: 0.05, green: 0.43, blue: 0.48)
    static let glassTint = Color(red: 0.25, green: 0.50, blue: 0.54)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.54)
    static let danger = Color(red: 0.64, green: 0.28, blue: 0.33)
}

enum LiquidMetrics {
    static let cardRadius: CGFloat = 24
    static let prominentCardRadius: CGFloat = 26
    static let compactCardRadius: CGFloat = 18
    static let fieldRadius: CGFloat = 16
    static let pillRadius: CGFloat = 18
}

enum LiquidControlChrome {
    static let iconFillOpacity = 0.034
    static let iconInteractiveFillOpacity = 0.046
    static let iconGlassOpacity = 0.058
    static let iconInteractiveGlassOpacity = 0.078
}

enum LiquidIconButtonRole {
    case accent
    case muted
    case danger
    case neutral
    case custom(Color)

    var tint: Color {
        switch self {
        case .accent:
            return LiquidPalette.accent
        case .muted:
            return LiquidPalette.muted
        case .danger:
            return LiquidPalette.danger
        case .neutral:
            return LiquidPalette.glassTint
        case .custom(let color):
            return color
        }
    }
}

enum LiquidIconButtonProminence {
    case toolbar
    case dock
    case action
    case inline

    var defaultSize: CGFloat {
        switch self {
        case .toolbar:
            return 46
        case .dock:
            return 44
        case .action:
            return 52
        case .inline:
            return 40
        }
    }

    var glyphWeight: Font.Weight {
        switch self {
        case .toolbar:
            return .semibold
        case .dock, .action, .inline:
            return .bold
        }
    }

    var glyphLineScale: CGFloat {
        switch self {
        case .toolbar:
            return 1.08
        case .dock:
            return 1.20
        case .action:
            return 1.12
        case .inline:
            return 1.10
        }
    }

    func defaultGlyphSize(for controlSize: CGFloat) -> CGFloat {
        switch self {
        case .toolbar:
            return min(20, controlSize * 0.43)
        case .dock:
            return min(22, controlSize * 0.50)
        case .action:
            return min(21, controlSize * 0.40)
        case .inline:
            return min(17, controlSize * 0.42)
        }
    }
}

struct LiquidIconButton: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    private let icon: BuybackIconKind?
    private let systemName: String?
    private let role: LiquidIconButtonRole
    private let size: CGFloat
    private let glyphSize: CGFloat?
    private let prominence: LiquidIconButtonProminence
    private let isSelected: Bool
    private let isDisabled: Bool
    private let showsGlyph: Bool

    init(
        icon: BuybackIconKind,
        role: LiquidIconButtonRole = .accent,
        size: CGFloat? = nil,
        glyphSize: CGFloat? = nil,
        prominence: LiquidIconButtonProminence = .action,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        showsGlyph: Bool = true
    ) {
        self.icon = icon
        self.systemName = nil
        self.role = role
        self.size = size ?? prominence.defaultSize
        self.glyphSize = glyphSize
        self.prominence = prominence
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.showsGlyph = showsGlyph
    }

    init(
        systemName: String,
        role: LiquidIconButtonRole = .accent,
        size: CGFloat? = nil,
        glyphSize: CGFloat? = nil,
        prominence: LiquidIconButtonProminence = .action,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        showsGlyph: Bool = true
    ) {
        self.icon = nil
        self.systemName = systemName
        self.role = role
        self.size = size ?? prominence.defaultSize
        self.glyphSize = glyphSize
        self.prominence = prominence
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.showsGlyph = showsGlyph
    }

    var body: some View {
        let shape = Circle()
        let effectiveDisabled = isDisabled || !isEnabled
        let resolvedGlyphSize = glyphSize ?? prominence.defaultGlyphSize(for: size)

        ZStack {
            buttonChrome(shape: shape, isDisabled: effectiveDisabled)

            if showsGlyph {
                glyph(size: resolvedGlyphSize, isDisabled: effectiveDisabled)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .scaleEffect(isSelected ? 1.018 : 1)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glyph(size: CGFloat, isDisabled: Bool) -> some View {
        let glyphTint = Color.white.opacity(isDisabled ? disabledGlyphOpacity : 0.98)
        let lineScale = prominence.glyphLineScale * (isDisabled ? 1.10 : 1)

        if let icon {
            BuybackIcon(icon, tint: glyphTint, lineScale: lineScale)
                .frame(width: size, height: size)
                .shadow(color: glyphShadowColor(isDisabled: isDisabled), radius: glyphShadowRadius, y: glyphShadowOffset)
        } else if let systemName {
            Image(systemName: systemName)
                .font(.system(size: size, weight: isDisabled ? .bold : prominence.glyphWeight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(glyphTint)
                .shadow(color: glyphShadowColor(isDisabled: isDisabled), radius: glyphShadowRadius, y: glyphShadowOffset)
        }
    }

    @ViewBuilder
    private func buttonChrome(shape: Circle, isDisabled: Bool) -> some View {
        let tint = role.tint

        if reduceTransparency {
            shape
                .fill(tint.opacity(reducedTransparencyFillOpacity(isDisabled: isDisabled)))
                .overlay {
                    shape.strokeBorder(strokeColor(isDisabled: isDisabled), lineWidth: strokeWidth)
                }
        } else if isDisabled {
            shape
                .fill(tint.opacity(fillOpacity(isDisabled: true)))
                .glassEffect(.regular.tint(tint.opacity(glassOpacity(isDisabled: true))), in: shape)
                .overlay {
                    shape.strokeBorder(strokeColor(isDisabled: true), lineWidth: strokeWidth)
                }
                .overlay {
                    shineOverlay(shape: shape, isDisabled: true)
                }
        } else {
            shape
                .fill(tint.opacity(fillOpacity(isDisabled: false)))
                .glassEffect(.regular.tint(tint.opacity(glassOpacity(isDisabled: false))).interactive(), in: shape)
                .overlay {
                    shape.strokeBorder(strokeColor(isDisabled: false), lineWidth: strokeWidth)
                }
                .overlay {
                    shineOverlay(shape: shape, isDisabled: false)
                }
                .shadow(color: shadowColor, radius: isSelected ? 13 : 8, y: isSelected ? 5 : 3)
        }
    }

    private func shineOverlay(shape: Circle, isDisabled: Bool) -> some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDisabled ? 0.035 : (isSelected ? 0.22 : 0.15)),
                        Color.white.opacity(isDisabled ? 0.010 : 0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
    }

    private var isHighContrast: Bool {
        colorSchemeContrast == .increased
    }

    private var strokeWidth: CGFloat {
        isSelected ? 1.15 : 0.85
    }

    private var disabledGlyphOpacity: Double {
        if colorScheme == .light {
            return isHighContrast ? 0.98 : 0.94
        }

        return isHighContrast ? 0.92 : 0.86
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.20 : 0.105)
    }

    private var glyphShadowRadius: CGFloat {
        prominence == .dock ? 2.4 : 1.35
    }

    private var glyphShadowOffset: CGFloat {
        prominence == .dock ? 1.05 : 0.8
    }

    private func glyphShadowColor(isDisabled: Bool) -> Color {
        if prominence == .dock {
            return Color.black.opacity(isDisabled ? 0.32 : 0.46)
        }

        return Color.black.opacity(isDisabled ? (colorScheme == .dark ? 0.24 : 0.30) : (colorScheme == .dark ? 0.32 : 0.24))
    }

    private func strokeColor(isDisabled: Bool) -> Color {
        if isDisabled {
            return Color.white.opacity(colorScheme == .dark ? 0.18 : 0.28)
        }

        if isSelected {
            return Color.white.opacity(colorScheme == .dark ? 0.34 : 0.46)
        }

        return Color.white.opacity(colorScheme == .dark ? 0.20 : 0.32)
    }

    private func fillOpacity(isDisabled: Bool) -> Double {
        let base: Double
        switch prominence {
        case .toolbar:
            base = 0.115
        case .dock:
            base = 0.118
        case .action:
            base = 0.124
        case .inline:
            base = 0.112
        }

        let selectedBoost = isSelected ? 0.044 : 0
        let contrastBoost = isHighContrast ? 0.040 : 0
        let lightModeBoost = colorScheme == .light ? 0.018 : 0
        let disabledReduction = isDisabled ? (colorScheme == .light ? 0.010 : 0.024) : 0
        return max(0.055, base + selectedBoost + contrastBoost + lightModeBoost - disabledReduction)
    }

    private func glassOpacity(isDisabled: Bool) -> Double {
        let base: Double
        switch prominence {
        case .toolbar:
            base = 0.135
        case .dock:
            base = 0.140
        case .action:
            base = 0.148
        case .inline:
            base = 0.130
        }

        let selectedBoost = isSelected ? 0.052 : 0
        let contrastBoost = isHighContrast ? 0.032 : 0
        let disabledReduction = isDisabled ? (colorScheme == .light ? 0.012 : 0.030) : 0
        return max(0.070, base + selectedBoost + contrastBoost - disabledReduction)
    }

    private func reducedTransparencyFillOpacity(isDisabled: Bool) -> Double {
        let base = isHighContrast ? 0.26 : 0.20
        let selectedBoost = isSelected ? 0.08 : 0
        let disabledReduction = isDisabled ? 0.035 : 0
        return max(0.12, base + selectedBoost - disabledReduction)
    }
}

struct LiquidGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        LiquidPalette.glassTint.opacity(0.035),
                        Color(uiColor: .systemGroupedBackground).opacity(0.86),
                        LiquidPalette.muted.opacity(0.024)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            LiquidPalette.glassTint.opacity(0.025),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 280)

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [
                            .clear,
                            LiquidPalette.glassTint.opacity(0.020),
                            LiquidPalette.muted.opacity(0.026)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 240)
                }

            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    let icon: BuybackIconKind

    init(_ title: String, icon: BuybackIconKind) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 9) {
            LiquidGlassIcon(icon: icon, tint: LiquidPalette.accent, size: 30)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

struct LiquidGlassIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let icon: BuybackIconKind
    let tint: Color
    let size: CGFloat
    var isInteractive = false

    var body: some View {
        let shape = Circle()

        BuybackIcon(icon, tint: tint)
            .padding(size * 0.24)
            .frame(width: size, height: size)
            .background {
                iconBackground(shape: shape)
            }
    }

    @ViewBuilder
    private func iconBackground(shape: Circle) -> some View {
        if reduceTransparency {
            shape
                .fill(tint.opacity(colorSchemeContrast == .increased ? 0.12 : 0.08))
                .overlay {
                    shape.strokeBorder(tint.opacity(0.22), lineWidth: 0.7)
                }
        } else if isInteractive {
            shape
                .fill(tint.opacity(LiquidControlChrome.iconInteractiveFillOpacity + (colorSchemeContrast == .increased ? 0.026 : 0)))
                .glassEffect(.regular.tint(tint.opacity(LiquidControlChrome.iconInteractiveGlassOpacity + 0.030)).interactive(), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.7)
                }
        } else {
            shape
                .fill(tint.opacity(LiquidControlChrome.iconFillOpacity + (colorSchemeContrast == .increased ? 0.018 : 0)))
                .overlay {
                    shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 0.7)
                }
        }
    }
}

struct LiquidGlassActionIcon: View {
    let icon: BuybackIconKind
    var tint: Color = LiquidPalette.accent
    var size: CGFloat = 42

    var body: some View {
        LiquidIconButton(
            icon: icon,
            role: .custom(tint),
            size: size,
            prominence: size <= 40 ? .inline : .action
        )
    }
}

struct LiquidToolbarIcon: View {
    let icon: BuybackIconKind
    var tint: Color = LiquidPalette.accent
    var iconSize: CGFloat = 19
    var controlSize: CGFloat = 44

    var body: some View {
        LiquidIconButton(
            icon: icon,
            role: .custom(tint),
            size: controlSize,
            glyphSize: iconSize,
            prominence: .toolbar
        )
    }
}

struct GlassBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidCapsuleSurface(tint: LiquidPalette.accent.opacity(0.55))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: BuybackIconKind

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LiquidGlassIcon(icon: icon, tint: LiquidPalette.accent, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.28))
    }
}

struct DropGauge: View {
    let dropPercent: Double

    private var progress: Double {
        min(max(dropPercent / 40, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Required pullback")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(dropPercent.percentString)
                    .font(.caption.monospacedDigit().weight(.bold))
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(LiquidPalette.accent)
                .frame(height: 10)
                .accessibilityLabel("Required pullback")
                .accessibilityValue(dropPercent.percentString)
        }
    }
}

private struct LiquidSurface: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .padding(prominent ? 18 : 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCardBackground(tint: prominent ? LiquidPalette.accent.opacity(0.36) : LiquidPalette.accent.opacity(0.16), prominent: prominent)
    }
}

private struct LiquidCardBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Color
    var prominent = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: prominent ? LiquidMetrics.prominentCardRadius : LiquidMetrics.cardRadius,
            style: .continuous
        )

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(prominent ? LiquidPalette.accent.opacity(0.040) : Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            shape.stroke(tint.opacity(0.20), lineWidth: 0.8)
                        }
                } else {
                    shape
                        .fill(
                            prominent
                                ? LiquidPalette.accent.opacity(0.034)
                                : Color(uiColor: .secondarySystemGroupedBackground).opacity(0.48)
                        )
                        .overlay {
                            shape.stroke(
                                LinearGradient(
                                    colors: [.white.opacity(prominent ? 0.34 : 0.22), tint.opacity(0.14), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                        }
                        .shadow(color: .black.opacity(0.045), radius: prominent ? 16 : 10, y: prominent ? 7 : 4)
                }
            }
    }
}

private struct LiquidFieldSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isFocused: Bool
    let isDisabled: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidMetrics.fieldRadius, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(LiquidPalette.glassTint.opacity(isDisabled ? 0.030 : 0.055))
                        .overlay {
                            shape.stroke(isFocused ? LiquidPalette.accent.opacity(0.64) : .secondary.opacity(0.22), lineWidth: isFocused ? 1.2 : 0.7)
                        }
                } else {
                    shape
                        .fill(LiquidPalette.glassTint.opacity(isDisabled ? 0.018 : 0.032))
                        .overlay {
                            shape.stroke(
                                isFocused ? LiquidPalette.accent.opacity(0.48) : .white.opacity(0.15),
                                lineWidth: isFocused ? 1.2 : 0.7
                            )
                        }
                }
            }
    }
}

private struct LiquidCapsuleSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidMetrics.pillRadius, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            shape.stroke(tint.opacity(0.18), lineWidth: 0.7)
                        }
                } else {
                    shape
                        .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.42))
                        .overlay {
                            shape.stroke(.white.opacity(0.16), lineWidth: 0.7)
                        }
                }
            }
    }
}

extension View {
    func liquidSurface(prominent: Bool = false) -> some View {
        modifier(LiquidSurface(prominent: prominent))
    }

    func liquidCardBackground(tint: Color, prominent: Bool = false) -> some View {
        modifier(LiquidCardBackground(tint: tint, prominent: prominent))
    }

    func liquidFieldSurface(isFocused: Bool = false, isDisabled: Bool = false) -> some View {
        modifier(LiquidFieldSurface(isFocused: isFocused, isDisabled: isDisabled))
    }

    func liquidCapsuleSurface(tint: Color) -> some View {
        modifier(LiquidCapsuleSurface(tint: tint))
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Double {
    var key: String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}
