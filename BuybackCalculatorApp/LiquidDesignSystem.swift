import SwiftUI

enum LiquidPalette {
    static let accent = Color(red: 0.02, green: 0.66, blue: 0.62)
    static let blue = Color(red: 0.20, green: 0.38, blue: 0.90)
    static let amber = Color(red: 0.90, green: 0.58, blue: 0.18)
    static let ink = Color(red: 0.02, green: 0.08, blue: 0.10)
}

struct LiquidGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        LiquidPalette.accent.opacity(0.16),
                        LiquidPalette.blue.opacity(0.08),
                        LiquidPalette.amber.opacity(0.10),
                        Color(uiColor: .systemBackground).opacity(0.68)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            LiquidPalette.accent.opacity(0.05),
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
                            LiquidPalette.blue.opacity(0.05),
                            LiquidPalette.ink.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 240)
                }

                MarketGridOverlay()
                    .opacity(0.42)
                    .blendMode(.softLight)
            }
        }
    }
}

private struct MarketGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            let rowHeight = max(size.height / 18, 28)
            var y: CGFloat = 0
            while y <= size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += rowHeight
            }

            let columnWidth = max(size.width / 9, 42)
            var x: CGFloat = 0
            while x <= size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += columnWidth
            }

            context.stroke(grid, with: .color(.white.opacity(0.16)), lineWidth: 0.6)

            var trend = Path()
            trend.move(to: CGPoint(x: 0, y: size.height * 0.58))
            trend.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.34),
                control1: CGPoint(x: size.width * 0.25, y: size.height * 0.47),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.68)
            )
            context.stroke(trend, with: .color(LiquidPalette.accent.opacity(0.18)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 9) {
            LiquidGlassIcon(systemImage: systemImage, tint: LiquidPalette.accent, size: 30)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

struct LiquidGlassIcon: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let systemImage: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        let shape = Circle()

        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                if reduceTransparency {
                    shape
                        .fill(tint.opacity(0.14))
                        .overlay {
                            shape.stroke(tint.opacity(0.22), lineWidth: 0.8)
                        }
                } else {
                    shape
                        .fill(tint.opacity(0.12))
                        .glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: shape)
                        .overlay {
                            shape.stroke(.white.opacity(0.26), lineWidth: 0.8)
                        }
                        .shadow(color: tint.opacity(0.14), radius: 10, y: 4)
                }
            }
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
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LiquidGlassIcon(systemImage: systemImage, tint: LiquidPalette.accent, size: 34)

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

            GeometryReader { proxy in
                let width = max(10, proxy.size.width * progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.08))
                        .glassEffect(.regular, in: Capsule())

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [LiquidPalette.amber, LiquidPalette.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width)
                        .shadow(color: LiquidPalette.accent.opacity(0.28), radius: 8, y: 2)
                }
            }
            .frame(height: 10)
        }
    }
}

private struct LiquidSurface: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .padding(prominent ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidCardBackground(tint: prominent ? LiquidPalette.accent.opacity(0.52) : LiquidPalette.blue.opacity(0.20), prominent: prominent)
    }
}

private struct LiquidCardBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tint: Color
    var prominent = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(prominent ? LiquidPalette.accent.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            shape.stroke(tint.opacity(0.24), lineWidth: 0.8)
                        }
                } else {
                    shape
                        .fill(
                            prominent
                                ? LiquidPalette.accent.opacity(0.13)
                                : Color(uiColor: .secondarySystemGroupedBackground).opacity(0.58)
                        )
                        .glassEffect(
                            prominent ? .regular.tint(tint).interactive() : .regular.tint(tint.opacity(0.45)).interactive(),
                            in: shape
                        )
                        .overlay {
                            shape.stroke(
                                LinearGradient(
                                    colors: [.white.opacity(prominent ? 0.38 : 0.24), tint.opacity(0.22), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                        }
                        .shadow(color: .black.opacity(0.06), radius: prominent ? 18 : 12, y: prominent ? 8 : 5)
                }
            }
    }
}

private struct LiquidFieldSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isFocused: Bool
    let isDisabled: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(.primary.opacity(isDisabled ? 0.035 : 0.07))
                        .overlay {
                            shape.stroke(isFocused ? LiquidPalette.accent.opacity(0.72) : .secondary.opacity(0.24), lineWidth: isFocused ? 1.2 : 0.7)
                        }
                } else {
                    shape
                        .fill(.primary.opacity(isDisabled ? 0.026 : 0.048))
                        .glassEffect(.regular.tint(LiquidPalette.accent.opacity(isFocused ? 0.16 : 0.06)).interactive(), in: shape)
                        .overlay {
                            shape.stroke(
                                isFocused ? LiquidPalette.accent.opacity(0.62) : .white.opacity(0.16),
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
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            shape.stroke(tint.opacity(0.22), lineWidth: 0.7)
                        }
                } else {
                    shape
                        .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.48))
                        .glassEffect(.regular.tint(tint.opacity(0.30)), in: shape)
                        .overlay {
                            shape.stroke(.white.opacity(0.18), lineWidth: 0.7)
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
