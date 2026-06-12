import WidgetKit
import SwiftUI
import AppIntents

enum WidgetTaxProfile: String, AppEnum {
    case germany
    case usLongTerm
    case usShortTerm
    case custom

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tax Profile")

    static let caseDisplayRepresentations: [WidgetTaxProfile: DisplayRepresentation] = [
        .germany: "Germany",
        .usLongTerm: "US long",
        .usShortTerm: "US short",
        .custom: "Custom"
    ]

    var taxProfile: TaxProfile {
        TaxProfile(rawValue: rawValue) ?? BuybackCalculator.defaultTaxProfile
    }
}

struct BuybackWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Buy-Back Calculator"
    static let description = IntentDescription("Calculate the buy-back price from a symbol, current gain, and live or fallback price.")

    @Parameter(title: "Stock Symbol", default: "AAPL")
    var symbol: String

    @Parameter(title: "Gain %", default: 463.10)
    var gainAtSellPercent: Double

    @Parameter(title: "Fallback Price", default: 185.0)
    var fallbackSellPrice: Double

    @Parameter(title: "Tax Profile", default: .germany)
    var taxProfile: WidgetTaxProfile

    @Parameter(title: "Tax Rate %", default: 27.0)
    var taxRatePercent: Double

    @Parameter(title: "Tax Currency", default: "USD")
    var taxCurrency: String

    @Parameter(title: "FX to Tax Currency", default: 1.0)
    var fxRateToTaxCurrency: Double

    @Parameter(title: "Extra Shares Target %", default: 2.5)
    var targetExtraSharesPercent: Double

    @Parameter(title: "Sell Fees", default: 0.0)
    var sellFeeTotal: Double

    @Parameter(title: "Buy Fees", default: 0.0)
    var buyFeeTotal: Double

    @Parameter(title: "Slippage %", default: 0.0)
    var slippagePercent: Double
}

struct BuybackEntry: TimelineEntry, Sendable {
    let date: Date
    let symbol: String
    let gainAtSellPercent: Double
    let fallbackSellPrice: Double
    let quote: MarketQuote?
    let priceStatus: WidgetPriceStatus
    let calculation: BuybackCalculation?
}

enum WidgetPriceStatus: Equatable, Sendable {
    case live
    case fallback(String)

    var label: String {
        switch self {
        case .live:
            return "Live"
        case .fallback:
            return "Fallback"
        }
    }

    var icon: BuybackIconKind {
        switch self {
        case .live:
            return .live
        case .fallback:
            return .warning
        }
    }
}

struct BuybackProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuybackEntry {
        makeFallbackEntry(
            configuration: BuybackWidgetConfiguration(),
            date: .now,
            reason: "Preview"
        )
    }

    func snapshot(
        for configuration: BuybackWidgetConfiguration,
        in context: Context
    ) async -> BuybackEntry {
        await makeEntry(configuration: configuration)
    }

    func timeline(
        for configuration: BuybackWidgetConfiguration,
        in context: Context
    ) async -> Timeline<BuybackEntry> {
        let entry = await makeEntry(configuration: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
    }

    private func makeEntry(
        configuration: BuybackWidgetConfiguration,
        date: Date = .now
    ) async -> BuybackEntry {
        let normalizedSymbol = configuration.symbol.normalizedStockSymbol
        let asset = MarketAsset(
            symbol: normalizedSymbol,
            name: normalizedSymbol,
            currencyCode: BuybackCalculator.defaultCurrencyCode,
            source: .finnhub
        )

        guard let client = MarketDataClientFactory.make() else {
            return makeFallbackEntry(
                configuration: configuration,
                date: date,
                reason: "Missing API key"
            )
        }

        do {
            let quote = try await client.quote(for: asset)
            let calculation = BuybackCalculator.calculate(
                symbol: normalizedSymbol,
                sellPrice: quote.price,
                gainAtSellPercent: configuration.gainAtSellPercent,
                sharesToSell: 1,
                taxProfile: configuration.taxProfile.taxProfile,
                taxRatePercent: configuration.taxRatePercent,
                taxCurrencyCode: configuration.taxCurrency,
                fxRateToTaxCurrency: configuration.fxRateToTaxCurrency,
                targetExtraSharesPercent: configuration.targetExtraSharesPercent,
                sellFeeTotal: configuration.sellFeeTotal,
                buyFeeTotal: configuration.buyFeeTotal,
                slippagePercent: configuration.slippagePercent,
                currencyCode: quote.currencyCode
            )

            return BuybackEntry(
                date: date,
                symbol: normalizedSymbol,
                gainAtSellPercent: configuration.gainAtSellPercent,
                fallbackSellPrice: configuration.fallbackSellPrice,
                quote: quote,
                priceStatus: .live,
                calculation: calculation
            )
        } catch {
            return makeFallbackEntry(
                configuration: configuration,
                date: date,
                reason: fallbackReason(for: error)
            )
        }
    }

    private func makeFallbackEntry(
        configuration: BuybackWidgetConfiguration,
        date: Date,
        reason: String
    ) -> BuybackEntry {
        let normalizedSymbol = configuration.symbol.normalizedStockSymbol
        let calculation = BuybackCalculator.calculate(
            symbol: normalizedSymbol,
            sellPrice: configuration.fallbackSellPrice,
            gainAtSellPercent: configuration.gainAtSellPercent,
            sharesToSell: 1,
            taxProfile: configuration.taxProfile.taxProfile,
            taxRatePercent: configuration.taxRatePercent,
            taxCurrencyCode: configuration.taxCurrency,
            fxRateToTaxCurrency: configuration.fxRateToTaxCurrency,
            targetExtraSharesPercent: configuration.targetExtraSharesPercent,
            sellFeeTotal: configuration.sellFeeTotal,
            buyFeeTotal: configuration.buyFeeTotal,
            slippagePercent: configuration.slippagePercent,
            currencyCode: BuybackCalculator.defaultCurrencyCode
        )

        return BuybackEntry(
            date: date,
            symbol: normalizedSymbol,
            gainAtSellPercent: configuration.gainAtSellPercent,
            fallbackSellPrice: configuration.fallbackSellPrice,
            quote: nil,
            priceStatus: .fallback(reason),
            calculation: calculation
        )
    }

    private func fallbackReason(for error: Error) -> String {
        if let marketDataError = error as? MarketDataError {
            switch marketDataError {
            case .missingAPIKey:
                return "Missing key"
            case .rateLimited:
                return "Rate limit"
            case .noResults:
                return "No result"
            case .quoteUnavailable:
                return "No quote"
            case .badStatusCode(let statusCode):
                return "HTTP \(statusCode)"
            case .invalidURL, .invalidResponse:
                return "Data error"
            }
        }
        return "Quote unavailable"
    }
}

struct BuybackWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BuybackEntry

    var body: some View {
        Group {
            if let calculation = entry.calculation {
                content(calculation)
            } else {
                invalidView
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            BuybackWidgetBackground()
        }
        .widgetURL(deepLinkURL)
    }

    private var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = "buybackcalculator"
        components.host = "calculator"
        var queryItems = [
            URLQueryItem(name: "symbol", value: entry.symbol),
            URLQueryItem(name: "price", value: activePrice.inputString),
            URLQueryItem(name: "gain", value: entry.gainAtSellPercent.inputString),
            URLQueryItem(name: "fallbackPrice", value: entry.fallbackSellPrice.inputString)
        ]
        if let calculation = entry.calculation {
            queryItems.append(URLQueryItem(name: "taxProfile", value: calculation.taxProfile.rawValue))
            queryItems.append(URLQueryItem(name: "taxRate", value: calculation.taxRatePercent.inputString))
            queryItems.append(URLQueryItem(name: "taxCurrency", value: calculation.taxCurrencyCode))
            queryItems.append(URLQueryItem(name: "fxRate", value: calculation.fxRateToTaxCurrency.inputString))
        }
        components.queryItems = queryItems
        return components.url
    }

    private var activePrice: Double {
        entry.quote?.price ?? entry.fallbackSellPrice
    }

    @ViewBuilder
    private func content(_ calculation: BuybackCalculation) -> some View {
        switch family {
        case .systemSmall:
            smallView(calculation)
        case .systemLarge:
            largeView(calculation)
        default:
            mediumView(calculation)
        }
    }

    private var contentPadding: EdgeInsets {
        switch family {
        case .systemSmall:
            EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        case .systemLarge:
            EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        default:
            EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        }
    }

    private func smallView(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(entry: entry, compact: true)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.54)
                    .lineLimit(1)
                    .widgetAccentable()

                Text("buy-back limit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                CompactMetric(title: "Price", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode))
                CompactMetric(title: "Drop", value: calculation.requiredDropPercent.compactPercentString)
            }
        }
    }

    private func mediumView(_ calculation: BuybackCalculation) -> some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 9) {
                WidgetHeader(entry: entry, compact: false)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    Text(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.60)
                        .lineLimit(1)
                        .widgetAccentable()

                    Text("Max for +\(calculation.targetExtraSharesPercent.compactPercentString) shares after tax")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                DropBar(dropPercent: calculation.requiredDropPercent)
            }

            VStack(spacing: 8) {
                MetricTile(title: "Price", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode), icon: .price, tint: .blue)
                MetricTile(title: "Gain", value: calculation.gainAtSellPercent.compactPercentString, icon: .percent, tint: .indigo)
                MetricTile(title: entry.priceStatus.label, value: statusValue, icon: entry.priceStatus.icon, tint: statusTint)
            }
            .frame(width: 114)
        }
    }

    private func largeView(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            WidgetHeader(entry: entry, compact: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode))
                    .font(.system(size: 43, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .widgetAccentable()

                Text("Maximum buy-back price from \(calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode)) and \(calculation.gainAtSellPercent.compactPercentString) gain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            DropBar(dropPercent: calculation.requiredDropPercent)

            Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 9) {
                GridRow {
                    MetricTile(title: "Price", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode), icon: .price, tint: .blue)
                    MetricTile(title: "Gain", value: calculation.gainAtSellPercent.compactPercentString, icon: .percent, tint: .indigo)
                }

                GridRow {
                    MetricTile(title: "Basis", value: calculation.averageCostBasis.moneyString(currencyCode: calculation.currencyCode), icon: .basis, tint: .green)
                    MetricTile(title: "Drop", value: calculation.requiredDropPercent.compactPercentString, icon: .drop, tint: .orange)
                }

                GridRow {
                    MetricTile(title: "Tax", value: calculation.taxAmount.moneyString(currencyCode: calculation.currencyCode), icon: .tax, tint: .mint)
                    MetricTile(title: entry.priceStatus.label, value: statusValue, icon: entry.priceStatus.icon, tint: statusTint)
                }
            }
        }
    }

    private var statusValue: String {
        switch entry.priceStatus {
        case .live:
            return entry.quote?.timestamp?.formatted(date: .omitted, time: .shortened) ?? "Now"
        case .fallback(let reason):
            return reason
        }
    }

    private var statusTint: Color {
        switch entry.priceStatus {
        case .live:
            return .teal
        case .fallback:
            return .orange
        }
    }

    private var invalidView: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            BuybackIcon(.warning, tint: .orange)
                .frame(width: family == .systemSmall ? 24 : 30, height: family == .systemSmall ? 24 : 30)
                .widgetAccentable()

            Text("Check widget inputs")
                .font(family == .systemSmall ? .headline : .title3.weight(.bold))
                .lineLimit(1)

            Text("Use Edit Widget to set a symbol, gain above -100%, and fallback price above 0.")
                .font(family == .systemSmall ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 4 : 3)

            Spacer(minLength: 0)
        }
    }
}

private struct WidgetHeader: View {
    let entry: BuybackEntry
    let compact: Bool

    var body: some View {
        HStack(spacing: 7) {
            BuybackIcon(entry.priceStatus.icon, tint: statusTint)
                .widgetAccentable()
                .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                .background {
                    Circle()
                        .fill(statusTint.opacity(0.12))
                        .glassEffect(.regular.tint(statusTint.opacity(0.18)), in: Circle())
                }

            Text(entry.symbol.isEmpty ? "Stock" : entry.symbol)
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(entry.priceStatus.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(statusTint)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTint: Color {
        switch entry.priceStatus {
        case .live:
            return .teal
        case .fallback:
            return .orange
        }
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .minimumScaleFactor(0.58)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            shape
                .fill(.primary.opacity(0.052))
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.12), lineWidth: 0.6)
                }
        }
    }
}

private struct MetricTile: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let title: String
    let value: String
    let icon: BuybackIconKind
    let tint: Color

    private var resolvedTint: Color {
        renderingMode == .fullColor ? tint : .primary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            BuybackIcon(icon, tint: resolvedTint)
                .frame(width: 15, height: 15)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.48)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            shape
                .fill(resolvedTint.opacity(renderingMode == .fullColor ? 0.11 : 0.055))
                .glassEffect(.regular.tint(resolvedTint.opacity(renderingMode == .fullColor ? 0.14 : 0.04)), in: shape)
                .overlay {
                    shape.stroke(.white.opacity(renderingMode == .fullColor ? 0.14 : 0.08), lineWidth: 0.6)
                }
        }
    }
}

private struct DropBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let dropPercent: Double

    private var progress: Double {
        min(max(dropPercent / 40, 0), 1)
    }

    private var fillColor: Color {
        renderingMode == .fullColor ? .orange : .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Required drop")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(dropPercent.compactPercentString)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.16))
                        .glassEffect(.regular, in: Capsule())

                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(8, proxy.size.width * progress))
                        .widgetAccentable()
                }
            }
            .frame(height: 7)
        }
    }
}

private struct BuybackWidgetBackground: View {
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.background)

            LinearGradient(
                colors: [
                    .teal.opacity(0.18),
                    .blue.opacity(0.10),
                    .orange.opacity(0.08),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)

                Spacer(minLength: 0)
            }
        }
    }
}

struct BuybackWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: BuybackWidgetKind.value,
            intent: BuybackWidgetConfiguration.self,
            provider: BuybackProvider()
        ) { entry in
            BuybackWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Buy-Back Calculator")
        .description("Uses a live quote when available and falls back to the configured price.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
        .supportedMountingStyles([.elevated, .recessed])
    }
}

private enum BuybackWidgetKind {
    static let value = "BuybackWidget"
}

private extension BuybackEntry {
    static let previewLive = BuybackEntry(
        date: .now,
        symbol: "AAPL",
        gainAtSellPercent: 463.10,
        fallbackSellPrice: 185,
        quote: MarketQuote(
            symbol: "AAPL",
            price: 185,
            currencyCode: "USD",
            timestamp: .now,
            source: .finnhub,
            isStale: false,
            statusMessage: nil
        ),
        priceStatus: .live,
        calculation: BuybackCalculator.calculate(
            symbol: "AAPL",
            sellPrice: 185,
            gainAtSellPercent: 463.10
        )
    )

    static let previewFallback = BuybackEntry(
        date: .now,
        symbol: "AAPL",
        gainAtSellPercent: 463.10,
        fallbackSellPrice: 185,
        quote: nil,
        priceStatus: .fallback("Missing key"),
        calculation: BuybackCalculator.calculate(
            symbol: "AAPL",
            sellPrice: 185,
            gainAtSellPercent: 463.10
        )
    )

    static let previewInvalid = BuybackEntry(
        date: .now,
        symbol: "",
        gainAtSellPercent: -120,
        fallbackSellPrice: 0,
        quote: nil,
        priceStatus: .fallback("Invalid"),
        calculation: nil
    )
}

#Preview("Small", as: .systemSmall) {
    BuybackWidget()
} timeline: {
    BuybackEntry.previewLive
}

#Preview("Medium", as: .systemMedium) {
    BuybackWidget()
} timeline: {
    BuybackEntry.previewFallback
}

#Preview("Large", as: .systemLarge) {
    BuybackWidget()
} timeline: {
    BuybackEntry.previewLive
}

#Preview("Invalid", as: .systemMedium) {
    BuybackWidget()
} timeline: {
    BuybackEntry.previewInvalid
}
