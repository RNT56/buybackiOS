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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let icon: BuybackIconKind
    let tint: Color
    let size: CGFloat

    var body: some View {
        let shape = Circle()

        BuybackIcon(icon, tint: tint)
            .padding(size * 0.24)
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
                        .fill(tint.opacity(0.13))
                        .overlay {
                            shape.stroke(.white.opacity(0.26), lineWidth: 0.8)
                        }
                        .shadow(color: tint.opacity(0.14), radius: 10, y: 4)
                }
            }
    }
}

struct LiquidGlassActionIcon: View {
    @Environment(\.isEnabled) private var isEnabled

    let icon: BuybackIconKind
    var tint: Color = LiquidPalette.accent
    var size: CGFloat = 42

    var body: some View {
        LiquidGlassIcon(icon: icon, tint: tint, size: size)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.38)
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
