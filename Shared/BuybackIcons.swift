import SwiftUI

enum BuybackIconKind: String, CaseIterable, Sendable {
    case appMark
    case settings
    case refresh
    case asset
    case lookupText
    case key
    case apiKey
    case live
    case save
    case clear
    case calculator
    case edit
    case taxProfile
    case tax
    case taxCurrency
    case taxRate
    case lots
    case sliders
    case price
    case percent
    case shares
    case fx
    case target
    case slippage
    case sellFee
    case buyFee
    case limit
    case drop
    case basis
    case cash
    case buybackCash
    case costs
    case sensitivity
    case scenarios
    case bookmark
    case alert
    case alertArmed
    case alertOff
    case widget
    case market
    case selected
    case warning
    case info
    case chevron
}

struct BuybackIcon: View {
    let kind: BuybackIconKind
    var tint: Color = .primary
    var lineScale: CGFloat = 1

    init(_ kind: BuybackIconKind, tint: Color = .primary, lineScale: CGFloat = 1) {
        self.kind = kind
        self.tint = tint
        self.lineScale = lineScale
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(BuybackIconDrawing.commands(for: kind, size: proxy.size, lineScale: lineScale).enumerated()), id: \.offset) { _, command in
                    command.view(tint: tint)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct IconLabel: View {
    let title: String
    let icon: BuybackIconKind
    var tint: Color = .primary
    var iconSize: CGFloat = 17
    var spacing: CGFloat = 7

    init(_ title: String, icon: BuybackIconKind, tint: Color = .primary, iconSize: CGFloat = 17, spacing: CGFloat = 7) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.iconSize = iconSize
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            BuybackIcon(icon, tint: tint)
                .frame(width: iconSize, height: iconSize)

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private enum BuybackIconDrawing {
    static func commands(
        for kind: BuybackIconKind,
        size: CGSize,
        lineScale: CGFloat
    ) -> [IconDrawCommand] {
        var commands: [IconDrawCommand] = []
        draw(kind, size: size, lineScale: lineScale) { command in
            commands.append(command)
        }
        return commands
    }

    private static func draw(
        _ kind: BuybackIconKind,
        size: CGSize,
        lineScale: CGFloat,
        emit: (IconDrawCommand) -> Void
    ) {
        let box = IconBox(size: size)
        let baseLine = max(box.side * 0.075 * lineScale, 1.35)
        let thinLine = max(box.side * 0.055 * lineScale, 1)
        let heavyLine = max(box.side * 0.095 * lineScale, 1.7)

        func stroke(_ path: Path, opacity: Double = 1, width: CGFloat? = nil) {
            emit(.stroke(path, opacity: opacity, width: width ?? baseLine))
        }

        func fill(_ path: Path, opacity: Double = 0.18) {
            emit(.fill(path, opacity: opacity))
        }

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
            var path = Path()
            path.move(to: box.point(x1, y1))
            path.addLine(to: box.point(x2, y2))
            return path
        }

        func poly(_ points: [(CGFloat, CGFloat)], closed: Bool = false) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: box.point(first.0, first.1))
            for point in points.dropFirst() {
                path.addLine(to: box.point(point.0, point.1))
            }
            if closed {
                path.closeSubpath()
            }
            return path
        }

        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
            Path(ellipseIn: box.rect(x - radius, y - radius, radius * 2, radius * 2))
        }

        func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 0.08) -> Path {
            Path(roundedRect: box.rect(x, y, width, height), cornerRadius: box.side * radius)
        }

        func arc(centerX: CGFloat, centerY: CGFloat, radius: CGFloat, start: Double, end: Double, clockwise: Bool = false) -> Path {
            var path = Path()
            path.addArc(
                center: box.point(centerX, centerY),
                radius: box.side * radius,
                startAngle: .degrees(start),
                endAngle: .degrees(end),
                clockwise: clockwise
            )
            return path
        }

        func arrowHead(at point: (CGFloat, CGFloat), left: (CGFloat, CGFloat), right: (CGFloat, CGFloat), opacity: Double = 1) {
            fill(poly([left, point, right], closed: true), opacity: opacity)
        }

        switch kind {
        case .appMark:
            stroke(arc(centerX: 0.5, centerY: 0.5, radius: 0.31, start: 30, end: 220), width: heavyLine)
            stroke(arc(centerX: 0.5, centerY: 0.5, radius: 0.31, start: 210, end: 400), width: heavyLine)
            arrowHead(at: (0.24, 0.29), left: (0.36, 0.27), right: (0.28, 0.41))
            arrowHead(at: (0.76, 0.71), left: (0.64, 0.73), right: (0.72, 0.59))
            stroke(line(0.33, 0.55, 0.67, 0.42), opacity: 0.55, width: thinLine)

        case .settings:
            stroke(circle(0.5, 0.5, 0.18), width: heavyLine)
            for angle in stride(from: CGFloat(0), to: CGFloat(360), by: CGFloat(45)) {
                let radians = angle * .pi / 180
                let inner = box.point(0.5 + cos(radians) * 0.30, y: 0.5 + sin(radians) * 0.30)
                let outer = box.point(0.5 + cos(radians) * 0.40, y: 0.5 + sin(radians) * 0.40)
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                stroke(path, opacity: 0.95, width: thinLine)
            }

        case .refresh:
            stroke(arc(centerX: 0.5, centerY: 0.5, radius: 0.31, start: 35, end: 250), width: heavyLine)
            stroke(arc(centerX: 0.5, centerY: 0.5, radius: 0.31, start: 215, end: 430), width: heavyLine)
            arrowHead(at: (0.21, 0.62), left: (0.18, 0.47), right: (0.34, 0.55))
            arrowHead(at: (0.79, 0.38), left: (0.82, 0.53), right: (0.66, 0.45))

        case .asset:
            stroke(circle(0.42, 0.42, 0.24), width: heavyLine)
            stroke(line(0.59, 0.59, 0.78, 0.78), width: heavyLine)
            stroke(poly([(0.28, 0.46), (0.39, 0.37), (0.49, 0.43), (0.56, 0.31)]), opacity: 0.65, width: thinLine)

        case .lookupText:
            stroke(line(0.22, 0.30, 0.74, 0.30), width: thinLine)
            stroke(line(0.22, 0.47, 0.62, 0.47), width: thinLine)
            stroke(line(0.22, 0.64, 0.70, 0.64), width: thinLine)
            stroke(line(0.76, 0.26, 0.76, 0.72), opacity: 0.75, width: heavyLine)

        case .key, .apiKey:
            stroke(circle(0.36, 0.43, 0.16), width: heavyLine)
            stroke(poly([(0.49, 0.53), (0.76, 0.80)]), width: heavyLine)
            stroke(line(0.65, 0.69, 0.73, 0.61), width: thinLine)
            if kind == .apiKey {
                stroke(circle(0.70, 0.28, 0.08), opacity: 0.7, width: thinLine)
                stroke(line(0.64, 0.34, 0.55, 0.42), opacity: 0.55, width: thinLine)
            }

        case .live:
            fill(poly([(0.55, 0.10), (0.27, 0.55), (0.48, 0.55), (0.40, 0.90), (0.75, 0.43), (0.53, 0.43)], closed: true), opacity: 0.78)

        case .save:
            stroke(roundedRect(0.20, 0.62, 0.60, 0.20, radius: 0.05), width: heavyLine)
            stroke(line(0.50, 0.18, 0.50, 0.56), width: heavyLine)
            arrowHead(at: (0.50, 0.60), left: (0.36, 0.45), right: (0.64, 0.45))

        case .clear:
            stroke(line(0.30, 0.35, 0.70, 0.35), width: heavyLine)
            stroke(line(0.42, 0.24, 0.58, 0.24), width: thinLine)
            stroke(poly([(0.36, 0.37), (0.40, 0.79), (0.60, 0.79), (0.64, 0.37)]), width: heavyLine)
            stroke(line(0.46, 0.47, 0.47, 0.69), opacity: 0.55, width: thinLine)
            stroke(line(0.54, 0.47, 0.53, 0.69), opacity: 0.55, width: thinLine)

        case .calculator:
            stroke(roundedRect(0.22, 0.14, 0.56, 0.72), width: heavyLine)
            stroke(line(0.33, 0.30, 0.67, 0.30), width: thinLine)
            for y in [0.48, 0.64] {
                for x in [0.35, 0.50, 0.65] {
                    fill(circle(x, y, 0.035), opacity: 0.85)
                }
            }

        case .edit:
            stroke(poly([(0.26, 0.72), (0.31, 0.56), (0.63, 0.24), (0.76, 0.37), (0.44, 0.69)]), width: heavyLine)
            stroke(line(0.58, 0.29, 0.71, 0.42), opacity: 0.6, width: thinLine)

        case .taxProfile:
            stroke(roundedRect(0.18, 0.21, 0.64, 0.58), width: heavyLine)
            stroke(circle(0.38, 0.43, 0.10), width: thinLine)
            stroke(arc(centerX: 0.38, centerY: 0.68, radius: 0.17, start: 205, end: 335), width: thinLine)
            stroke(line(0.56, 0.40, 0.72, 0.40), opacity: 0.65, width: thinLine)
            stroke(line(0.56, 0.56, 0.72, 0.56), opacity: 0.65, width: thinLine)

        case .tax:
            stroke(poly([(0.20, 0.37), (0.50, 0.18), (0.80, 0.37)]), width: heavyLine)
            stroke(line(0.25, 0.77, 0.75, 0.77), width: heavyLine)
            for x in [0.33, 0.50, 0.67] {
                stroke(line(x, 0.42, x, 0.70), width: thinLine)
            }

        case .taxCurrency:
            stroke(circle(0.50, 0.50, 0.31), width: heavyLine)
            stroke(line(0.50, 0.24, 0.50, 0.76), width: thinLine)
            stroke(poly([(0.63, 0.34), (0.43, 0.34), (0.37, 0.46), (0.62, 0.54), (0.56, 0.66), (0.36, 0.66)]), width: thinLine)

        case .taxRate, .percent:
            stroke(circle(0.34, 0.34, 0.09), width: heavyLine)
            stroke(circle(0.66, 0.66, 0.09), width: heavyLine)
            stroke(line(0.30, 0.75, 0.70, 0.25), width: heavyLine)

        case .lots:
            stroke(roundedRect(0.16, 0.22, 0.68, 0.56), width: heavyLine)
            stroke(line(0.16, 0.41, 0.84, 0.41), opacity: 0.7, width: thinLine)
            stroke(line(0.16, 0.59, 0.84, 0.59), opacity: 0.7, width: thinLine)
            stroke(line(0.39, 0.22, 0.39, 0.78), opacity: 0.7, width: thinLine)
            stroke(line(0.62, 0.22, 0.62, 0.78), opacity: 0.7, width: thinLine)

        case .sliders:
            for (y, knob) in [(0.30, 0.62), (0.50, 0.36), (0.70, 0.70)] {
                stroke(line(0.18, y, 0.82, y), opacity: 0.65, width: thinLine)
                fill(circle(knob, y, 0.075), opacity: 0.85)
            }

        case .price:
            stroke(poly([(0.23, 0.25), (0.58, 0.22), (0.80, 0.44), (0.45, 0.80), (0.22, 0.57)], closed: true), width: heavyLine)
            fill(circle(0.50, 0.38, 0.055), opacity: 0.8)

        case .shares:
            stroke(line(0.30, 0.22, 0.23, 0.78), width: thinLine)
            stroke(line(0.55, 0.22, 0.48, 0.78), width: thinLine)
            stroke(line(0.20, 0.40, 0.78, 0.40), width: heavyLine)
            stroke(line(0.18, 0.61, 0.76, 0.61), width: heavyLine)

        case .fx:
            stroke(line(0.24, 0.36, 0.76, 0.36), width: heavyLine)
            arrowHead(at: (0.78, 0.36), left: (0.65, 0.27), right: (0.65, 0.45))
            stroke(line(0.76, 0.64, 0.24, 0.64), width: heavyLine)
            arrowHead(at: (0.22, 0.64), left: (0.35, 0.55), right: (0.35, 0.73))

        case .target:
            stroke(circle(0.50, 0.50, 0.31), width: heavyLine)
            stroke(circle(0.50, 0.50, 0.13), opacity: 0.75, width: thinLine)
            stroke(line(0.50, 0.18, 0.50, 0.31), opacity: 0.75, width: thinLine)
            stroke(line(0.50, 0.69, 0.50, 0.82), opacity: 0.75, width: thinLine)
            stroke(line(0.18, 0.50, 0.31, 0.50), opacity: 0.75, width: thinLine)
            stroke(line(0.69, 0.50, 0.82, 0.50), opacity: 0.75, width: thinLine)

        case .slippage:
            var path = Path()
            path.move(to: box.point(0.15, 0.55))
            path.addCurve(to: box.point(0.39, 0.55), control1: box.point(0.22, 0.31), control2: box.point(0.31, 0.79))
            path.addCurve(to: box.point(0.63, 0.55), control1: box.point(0.47, 0.31), control2: box.point(0.55, 0.79))
            path.addCurve(to: box.point(0.85, 0.55), control1: box.point(0.70, 0.35), control2: box.point(0.78, 0.70))
            stroke(path, width: heavyLine)

        case .sellFee, .buyFee:
            stroke(circle(0.56, 0.52, 0.23), width: heavyLine)
            stroke(line(0.56, 0.38, 0.56, 0.66), opacity: 0.55, width: thinLine)
            if kind == .sellFee {
                stroke(line(0.21, 0.34, 0.40, 0.34), width: heavyLine)
            } else {
                stroke(line(0.21, 0.34, 0.40, 0.34), width: heavyLine)
                stroke(line(0.305, 0.25, 0.305, 0.43), width: heavyLine)
            }

        case .limit:
            stroke(circle(0.50, 0.50, 0.30), width: heavyLine)
            stroke(line(0.27, 0.50, 0.73, 0.50), width: thinLine)
            stroke(line(0.50, 0.27, 0.50, 0.73), width: thinLine)
            fill(circle(0.50, 0.50, 0.045), opacity: 0.9)

        case .drop:
            stroke(poly([(0.28, 0.27), (0.48, 0.49), (0.60, 0.41), (0.75, 0.73)]), width: heavyLine)
            arrowHead(at: (0.76, 0.76), left: (0.61, 0.69), right: (0.75, 0.60))

        case .basis:
            stroke(roundedRect(0.17, 0.28, 0.66, 0.44), width: heavyLine)
            stroke(circle(0.50, 0.50, 0.12), opacity: 0.75, width: thinLine)
            stroke(line(0.26, 0.40, 0.26, 0.60), opacity: 0.55, width: thinLine)
            stroke(line(0.74, 0.40, 0.74, 0.60), opacity: 0.55, width: thinLine)

        case .cash, .buybackCash:
            stroke(roundedRect(0.18, 0.30, 0.64, 0.44), width: heavyLine)
            fill(circle(0.50, 0.52, 0.11), opacity: 0.55)
            if kind == .buybackCash {
                stroke(arc(centerX: 0.50, centerY: 0.52, radius: 0.22, start: 210, end: 35), opacity: 0.7, width: thinLine)
                arrowHead(at: (0.69, 0.40), left: (0.56, 0.37), right: (0.64, 0.52), opacity: 0.75)
            }

        case .costs:
            stroke(roundedRect(0.27, 0.17, 0.46, 0.66), width: heavyLine)
            stroke(line(0.36, 0.36, 0.64, 0.36), opacity: 0.7, width: thinLine)
            stroke(line(0.36, 0.50, 0.60, 0.50), opacity: 0.7, width: thinLine)
            stroke(line(0.36, 0.64, 0.66, 0.64), opacity: 0.7, width: thinLine)

        case .sensitivity:
            stroke(poly([(0.17, 0.70), (0.30, 0.55), (0.45, 0.58), (0.62, 0.35), (0.83, 0.28)]), width: heavyLine)
            fill(circle(0.30, 0.55, 0.055), opacity: 0.9)
            fill(circle(0.62, 0.35, 0.055), opacity: 0.9)
            stroke(line(0.17, 0.80, 0.83, 0.80), opacity: 0.45, width: thinLine)

        case .scenarios:
            stroke(roundedRect(0.17, 0.46, 0.66, 0.31), width: heavyLine)
            stroke(line(0.27, 0.36, 0.73, 0.36), opacity: 0.7, width: thinLine)
            stroke(line(0.34, 0.25, 0.66, 0.25), opacity: 0.45, width: thinLine)

        case .bookmark:
            fill(poly([(0.30, 0.18), (0.70, 0.18), (0.70, 0.82), (0.50, 0.67), (0.30, 0.82)], closed: true), opacity: 0.72)

        case .alert, .alertArmed, .alertOff:
            stroke(poly([(0.31, 0.62), (0.34, 0.42), (0.50, 0.28), (0.66, 0.42), (0.69, 0.62)]), width: heavyLine)
            stroke(line(0.27, 0.66, 0.73, 0.66), width: heavyLine)
            stroke(arc(centerX: 0.50, centerY: 0.66, radius: 0.12, start: 35, end: 145), opacity: 0.7, width: thinLine)
            if kind == .alertArmed {
                fill(circle(0.72, 0.30, 0.075), opacity: 0.9)
            } else if kind == .alertOff {
                stroke(line(0.24, 0.78, 0.78, 0.24), opacity: 0.85, width: heavyLine)
            }

        case .widget:
            stroke(roundedRect(0.18, 0.25, 0.43, 0.43), width: heavyLine)
            stroke(roundedRect(0.39, 0.39, 0.43, 0.43), opacity: 0.65, width: thinLine)

        case .market:
            stroke(line(0.21, 0.76, 0.21, 0.24), opacity: 0.55, width: thinLine)
            stroke(line(0.21, 0.76, 0.80, 0.76), opacity: 0.55, width: thinLine)
            stroke(poly([(0.26, 0.62), (0.40, 0.49), (0.52, 0.56), (0.69, 0.34), (0.80, 0.41)]), width: heavyLine)

        case .selected:
            stroke(circle(0.50, 0.50, 0.31), width: heavyLine)
            stroke(poly([(0.33, 0.51), (0.45, 0.63), (0.69, 0.39)]), width: heavyLine)

        case .warning:
            stroke(poly([(0.50, 0.18), (0.83, 0.77), (0.17, 0.77)], closed: true), width: heavyLine)
            stroke(line(0.50, 0.38, 0.50, 0.58), width: heavyLine)
            fill(circle(0.50, 0.68, 0.035), opacity: 0.95)

        case .info:
            stroke(circle(0.50, 0.50, 0.31), width: heavyLine)
            stroke(line(0.50, 0.45, 0.50, 0.66), width: heavyLine)
            fill(circle(0.50, 0.32, 0.035), opacity: 0.95)

        case .chevron:
            stroke(poly([(0.38, 0.26), (0.62, 0.50), (0.38, 0.74)]), width: heavyLine)
        }
    }
}

private struct IconBox {
    let size: CGSize

    var side: CGFloat {
        min(size.width, size.height)
    }

    private var origin: CGPoint {
        CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + side * x, y: origin.y + side * y)
    }

    func point(_ x: CGFloat, y: CGFloat) -> CGPoint {
        point(x, y)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + side * x,
            y: origin.y + side * y,
            width: side * width,
            height: side * height
        )
    }
}

private struct IconDrawCommand {
    enum Kind {
        case stroke(width: CGFloat)
        case fill
    }

    let kind: Kind
    let path: Path
    let opacity: Double

    static func stroke(_ path: Path, opacity: Double, width: CGFloat) -> IconDrawCommand {
        IconDrawCommand(kind: .stroke(width: width), path: path, opacity: opacity)
    }

    static func fill(_ path: Path, opacity: Double) -> IconDrawCommand {
        IconDrawCommand(kind: .fill, path: path, opacity: opacity)
    }

    @ViewBuilder
    func view(tint: Color) -> some View {
        switch kind {
        case .stroke(let width):
            path.stroke(
                tint.opacity(opacity),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        case .fill:
            path.fill(tint.opacity(opacity))
        }
    }
}
