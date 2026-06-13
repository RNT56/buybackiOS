import SwiftUI

enum LiquidPalette {
    static let accent = Color(red: 0.05, green: 0.43, blue: 0.48)
    static let glassTint = Color(red: 0.25, green: 0.50, blue: 0.54)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.54)
    static let danger = Color(red: 0.64, green: 0.28, blue: 0.33)
    static let ink = Color.primary
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
    static let actionFillOpacity = 0.054
    static let actionGlassOpacity = 0.082
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
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    shape.strokeBorder(.secondary.opacity(0.18), lineWidth: 0.7)
                }
        } else if isInteractive {
            shape
                .fill(LiquidPalette.glassTint.opacity(LiquidControlChrome.iconInteractiveFillOpacity))
                .glassEffect(.regular.tint(LiquidPalette.glassTint.opacity(LiquidControlChrome.iconInteractiveGlassOpacity)).interactive(), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.7)
                }
        } else {
            shape
                .fill(LiquidPalette.glassTint.opacity(LiquidControlChrome.iconFillOpacity))
                .glassEffect(.regular.tint(LiquidPalette.glassTint.opacity(LiquidControlChrome.iconGlassOpacity)), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.14 : 0.22), lineWidth: 0.7)
                }
        }
    }
}

struct LiquidGlassActionIcon: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let icon: BuybackIconKind
    var tint: Color = LiquidPalette.accent
    var size: CGFloat = 42

    var body: some View {
        let shape = Circle()

        ZStack {
            actionBackground(shape: shape)

            BuybackIcon(icon, tint: .white.opacity(isEnabled ? 0.97 : 0.62), lineScale: 1.10)
                .frame(width: size * 0.44, height: size * 0.44)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.18), radius: 1.4, y: 0.8)
        }
            .frame(width: size, height: size)
            .contentShape(Circle())
    }

    @ViewBuilder
    private func actionBackground(shape: Circle) -> some View {
        if reduceTransparency {
            shape
                .fill(LiquidPalette.glassTint.opacity(0.16))
                .overlay {
                    shape.strokeBorder(.secondary.opacity(0.20), lineWidth: 0.8)
                }
        } else {
            shape
                .fill(LiquidPalette.glassTint.opacity(LiquidControlChrome.actionFillOpacity))
                .glassEffect(.regular.tint(LiquidPalette.glassTint.opacity(LiquidControlChrome.actionGlassOpacity)).interactive(), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.26), lineWidth: 0.8)
                }
        }
    }
}

struct LiquidToolbarIcon: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let icon: BuybackIconKind
    var tint: Color = LiquidPalette.accent
    var iconSize: CGFloat = 19
    var controlSize: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(LiquidPalette.glassTint.opacity(reduceTransparency ? 0.12 : LiquidControlChrome.actionFillOpacity))
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.8)
                }

            BuybackIcon(icon, tint: .white.opacity(isEnabled ? 0.96 : 0.56), lineScale: 1.08)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.18), radius: 1.2, y: 0.8)
        }
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
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
