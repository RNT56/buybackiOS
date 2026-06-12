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
    static let description = IntentDescription("Calculate the buy-back price from a stock symbol, company name, ISIN, or WKN.")

    @Parameter(title: "Stock, ISIN, or WKN", description: "Ticker, company name, ISIN, or WKN.", default: "AAPL")
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
    let query: String
    let symbol: String
    let assetName: String?
    let assetExchange: String?
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

private enum WidgetMetrics {
    static func contentPadding(for family: WidgetFamily) -> EdgeInsets {
        switch family {
        case .systemSmall:
            EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        case .systemLarge:
            EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        default:
            EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        }
    }

    static func surfaceRadius(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 15
        case .systemLarge:
            return 20
        default:
            return 18
        }
    }

    static func pillRadius(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 12
        case .systemLarge:
            return 15
        default:
            return 14
        }
    }

    static func iconBubbleSize(compact: Bool) -> CGFloat {
        compact ? 30 : 34
    }

    static func iconSize(compact: Bool) -> CGFloat {
        compact ? 20 : 22
    }
}

private struct WidgetGlassSurface: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let tint: Color
    let radius: CGFloat
    let fillOpacity: Double
    let glassTintOpacity: Double
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape
                    .fill(tint.opacity(renderingMode == .fullColor ? fillOpacity : min(fillOpacity, 0.06)))
                    .glassEffect(
                        .regular.tint(tint.opacity(renderingMode == .fullColor ? glassTintOpacity : 0.035)),
                        in: shape
                    )
                    .overlay {
                        shape.stroke(.white.opacity(renderingMode == .fullColor ? strokeOpacity : 0.08), lineWidth: 0.7)
                    }
            }
    }
}

private extension View {
    func widgetGlassSurface(
        tint: Color = .primary,
        radius: CGFloat,
        fillOpacity: Double = 0.07,
        glassTintOpacity: Double = 0.08,
        strokeOpacity: Double = 0.12
    ) -> some View {
        modifier(
            WidgetGlassSurface(
                tint: tint,
                radius: radius,
                fillOpacity: fillOpacity,
                glassTintOpacity: glassTintOpacity,
                strokeOpacity: strokeOpacity
            )
        )
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
        let query = configuration.symbol.trimmedForDisplay
        let directAsset = fallbackAsset(for: query)

        guard let client = MarketDataClientFactory.make() else {
            return makeFallbackEntry(
                configuration: configuration,
                date: date,
                reason: "Missing API key",
                asset: directAsset
            )
        }

        do {
            let asset = try await resolveAsset(for: query, client: client)

            do {
                return try await makeLiveEntry(
                    configuration: configuration,
                    date: date,
                    query: query,
                    asset: asset,
                    client: client
                )
            } catch {
                return makeFallbackEntry(
                    configuration: configuration,
                    date: date,
                    reason: fallbackReason(for: error),
                    asset: asset
                )
            }
        } catch {
            return makeFallbackEntry(
                configuration: configuration,
                date: date,
                reason: fallbackReason(for: error),
                asset: directAsset
            )
        }
    }

    private func makeLiveEntry(
        configuration: BuybackWidgetConfiguration,
        date: Date,
        query: String,
        asset: MarketAsset,
        client: CompositeMarketDataClient
    ) async throws -> BuybackEntry {
        let quote = try await client.quote(for: asset)
        let calculation = BuybackCalculator.calculate(
            symbol: asset.symbol,
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
            query: query,
            symbol: asset.symbol,
            assetName: asset.name,
            assetExchange: asset.exchange.nilIfEmpty,
            gainAtSellPercent: configuration.gainAtSellPercent,
            fallbackSellPrice: configuration.fallbackSellPrice,
            quote: quote,
            priceStatus: .live,
            calculation: calculation
        )
    }

    private func makeFallbackEntry(
        configuration: BuybackWidgetConfiguration,
        date: Date,
        reason: String,
        asset: MarketAsset? = nil
    ) -> BuybackEntry {
        let query = configuration.symbol.trimmedForDisplay
        let fallbackAsset = asset ?? fallbackAsset(for: query)
        let calculation = BuybackCalculator.calculate(
            symbol: fallbackAsset.symbol,
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
            currencyCode: fallbackAsset.currencyCode
        )

        return BuybackEntry(
            date: date,
            query: query,
            symbol: fallbackAsset.symbol,
            assetName: fallbackAsset.name,
            assetExchange: fallbackAsset.exchange.nilIfEmpty,
            gainAtSellPercent: configuration.gainAtSellPercent,
            fallbackSellPrice: configuration.fallbackSellPrice,
            quote: nil,
            priceStatus: .fallback(reason),
            calculation: calculation
        )
    }

    private func resolveAsset(
        for query: String,
        client: CompositeMarketDataClient
    ) async throws -> MarketAsset {
        let cleanedQuery = query.trimmedForDisplay
        let fallbackAsset = fallbackAsset(for: cleanedQuery)

        guard cleanedQuery.count >= 2 else {
            return fallbackAsset
        }

        do {
            let matches = try await client.searchAssets(query: cleanedQuery)
            return preferredAsset(from: matches, matching: cleanedQuery) ?? fallbackAsset
        } catch {
            if cleanedQuery.normalizedStockSymbol == fallbackAsset.symbol,
               !fallbackAsset.symbol.isEmpty,
               !cleanedQuery.isLikelyISIN,
               !cleanedQuery.isLikelyWKN {
                return fallbackAsset
            }
            throw error
        }
    }

    private func preferredAsset(
        from assets: [MarketAsset],
        matching query: String
    ) -> MarketAsset? {
        let normalizedQuery = query.normalizedStockSymbol
        let upperQuery = query.trimmedForDisplay.uppercased()

        return assets.first { $0.symbol == normalizedQuery }
            ?? assets.first { $0.isin?.uppercased() == upperQuery || $0.wkn?.uppercased() == upperQuery }
            ?? assets.first { $0.name.localizedCaseInsensitiveContains(query.trimmedForDisplay) }
            ?? assets.first
    }

    private func fallbackAsset(for query: String) -> MarketAsset {
        let normalizedSymbol = query.normalizedStockSymbol
        let symbol = normalizedSymbol.isEmpty ? BuybackCalculator.defaultSymbol : normalizedSymbol

        return MarketAsset(
            symbol: symbol,
            name: query.nilIfEmpty ?? symbol,
            currencyCode: symbol.guessedCurrencyCode,
            source: .finnhub
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
        WidgetMetrics.contentPadding(for: family)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .widgetGlassSurface(
                tint: .teal,
                radius: WidgetMetrics.surfaceRadius(for: family),
                fillOpacity: 0.075,
                glassTintOpacity: 0.12,
                strokeOpacity: 0.13
            )

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

            Text("Set Stock, ISIN, or WKN in widget settings, with gain above -100% and fallback price above 0.")
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
        HStack(spacing: compact ? 7 : 9) {
            BuybackIcon(entry.priceStatus.icon, tint: statusTint)
                .widgetAccentable()
                .frame(width: WidgetMetrics.iconSize(compact: compact), height: WidgetMetrics.iconSize(compact: compact))
                .frame(width: WidgetMetrics.iconBubbleSize(compact: compact), height: WidgetMetrics.iconBubbleSize(compact: compact))
                .background {
                    Circle()
                        .fill(statusTint.opacity(0.12))
                        .glassEffect(.regular.tint(statusTint.opacity(0.18)), in: Circle())
                }

            VStack(alignment: .leading, spacing: compact ? 0 : 1) {
                Text(entry.symbol.isEmpty ? "Stock" : entry.symbol)
                    .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !compact, let descriptor {
                    Text(descriptor)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 4)

            WidgetStatusPill(status: entry.priceStatus)
        }
        .accessibilityElement(children: .combine)
    }

    private var descriptor: String? {
        let cleanedName = entry.assetName?.trimmedForDisplay
        let name = cleanedName.flatMap { $0.caseInsensitiveCompare(entry.symbol) == .orderedSame ? nil : $0.nilIfEmpty }
        let exchange = entry.assetExchange?.trimmedForDisplay.nilIfEmpty

        switch (name, exchange) {
        case (.some(let name), .some(let exchange)):
            return "\(name) - \(exchange)"
        case (.some(let name), .none):
            return name
        case (.none, .some(let exchange)):
            return exchange
        case (.none, .none):
            return nil
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
}

private struct WidgetStatusPill: View {
    @Environment(\.widgetFamily) private var family

    let status: WidgetPriceStatus

    var body: some View {
        HStack(spacing: 4) {
            BuybackIcon(status.icon, tint: tint)
                .frame(width: 11, height: 11)
                .widgetAccentable()

            Text(status.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, family == .systemSmall ? 7 : 8)
        .padding(.vertical, family == .systemSmall ? 4 : 5)
        .widgetGlassSurface(
            tint: tint,
            radius: WidgetMetrics.pillRadius(for: family),
            fillOpacity: 0.12,
            glassTintOpacity: 0.16,
            strokeOpacity: 0.14
        )
    }

    private var tint: Color {
        switch status {
        case .live:
            return .teal
        case .fallback:
            return .orange
        }
    }
}

private struct CompactMetric: View {
    @Environment(\.widgetFamily) private var family

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
        .widgetGlassSurface(
            radius: WidgetMetrics.surfaceRadius(for: family),
            fillOpacity: 0.052,
            glassTintOpacity: 0.04,
            strokeOpacity: 0.12
        )
    }
}

private struct MetricTile: View {
    @Environment(\.widgetFamily) private var family
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
        .widgetGlassSurface(
            tint: resolvedTint,
            radius: WidgetMetrics.surfaceRadius(for: family),
            fillOpacity: renderingMode == .fullColor ? 0.11 : 0.055,
            glassTintOpacity: renderingMode == .fullColor ? 0.14 : 0.04,
            strokeOpacity: renderingMode == .fullColor ? 0.14 : 0.08
        )
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
        .description("Resolves a stock symbol, company name, ISIN, or WKN, then uses a live quote when available.")
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
        query: "AAPL",
        symbol: "AAPL",
        assetName: "Apple Inc.",
        assetExchange: "US",
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
        query: "AAPL",
        symbol: "AAPL",
        assetName: "Apple Inc.",
        assetExchange: "US",
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
        query: "",
        symbol: "",
        assetName: nil,
        assetExchange: nil,
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
