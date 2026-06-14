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

struct BuybackPortfolioWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Buy-Back Portfolio"
    static let description = IntentDescription("Display saved assets with live prices and calculated buy-back limits.")
}

private enum FreezeScenarioIntentError: Error, LocalizedError {
    case invalidInput
    case scenarioNotFound

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "The scenario could not be frozen because the widget price is invalid."
        case .scenarioNotFound:
            return "The saved scenario no longer exists."
        }
    }
}

struct FreezeScenarioIntent: AppIntent {
    static let title: LocalizedStringResource = "Freeze Sell Price"
    static let description = IntentDescription("Freeze a saved scenario at the widget's latest displayed quote.")

    @Parameter(title: "Scenario ID")
    var scenarioID: String

    @Parameter(title: "Sell Price")
    var sellPrice: Double

    @Parameter(title: "Currency")
    var currencyCode: String

    @Parameter(title: "Quote Time")
    var quoteUnixTime: Double

    init() {
        scenarioID = ""
        sellPrice = 0
        currencyCode = BuybackCalculator.defaultCurrencyCode
        quoteUnixTime = 0
    }

    init(
        scenarioID: String,
        sellPrice: Double,
        currencyCode: String,
        quoteUnixTime: Double
    ) {
        self.scenarioID = scenarioID
        self.sellPrice = sellPrice
        self.currencyCode = currencyCode
        self.quoteUnixTime = quoteUnixTime
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: scenarioID),
              sellPrice.isFinite,
              sellPrice > 0
        else {
            throw FreezeScenarioIntentError.invalidInput
        }

        let quoteTimestamp = quoteUnixTime > 0 ? Date(timeIntervalSince1970: quoteUnixTime) : nil
        guard SavedScenarioStorage.freezeScenario(
            id: id,
            sellPrice: sellPrice,
            currencyCode: currencyCode,
            quoteTimestamp: quoteTimestamp
        ) else {
            throw FreezeScenarioIntentError.scenarioNotFound
        }

        WidgetCenter.shared.reloadTimelines(ofKind: BuybackWidgetKind.portfolio)
        return .result()
    }
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
    let alert: PriceAlert?
    let calculation: BuybackCalculation?
}

struct BuybackPortfolioEntry: TimelineEntry {
    let date: Date
    let rows: [BuybackPortfolioRow]
    let hasSavedScenarios: Bool
    let hasPinnedScenarios: Bool
    let pinnedCount: Int
}

struct BuybackPortfolioRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let symbol: String
    let assetName: String?
    let assetExchange: String?
    let quote: MarketQuote?
    let priceStatus: WidgetPriceStatus
    let alert: PriceAlert?
    let calculation: BuybackCalculation?
    let trackingState: ScenarioTrackingState
    let frozenSellPrice: Double?
    let currentMarketPrice: Double?
    let activeSellPrice: Double?
    let isBuybackReady: Bool
}

enum WidgetPriceStatus: Equatable, Sendable {
    case live
    case cached(String)
    case fallback(String)

    var label: String {
        switch self {
        case .live:
            return "Live"
        case .cached:
            return "Cached"
        case .fallback:
            return "Fallback"
        }
    }

    var icon: BuybackIconKind {
        switch self {
        case .live, .cached:
            return .live
        case .fallback:
            return .warning
        }
    }
}

private func widgetPriceStatus(for status: MarketQuoteRefreshStatus) -> WidgetPriceStatus {
    switch status {
    case .live:
        return .live
    case .cached:
        return .cached("Cached")
    case .cachedFallback(let reason):
        return .cached(reason)
    case .unavailable(let reason):
        return .fallback(reason)
    }
}

private func widgetFallbackReason(for status: MarketQuoteRefreshStatus) -> String {
    switch status {
    case .live:
        return "Live"
    case .cached:
        return "Cached"
    case .cachedFallback(let reason), .unavailable(let reason):
        return reason
    }
}

private enum WidgetMetrics {
    static func contentPadding(for family: WidgetFamily) -> EdgeInsets {
        switch family {
        case .systemSmall:
            EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        case .systemLarge:
            EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        default:
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        }
    }

    static func surfaceRadius(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 18
        case .systemLarge:
            return 24
        default:
            return 21
        }
    }

    static func pillRadius(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 14
        case .systemLarge:
            return 18
        default:
            return 16
        }
    }

    static func iconSurfaceRadius(for size: CGFloat) -> CGFloat {
        max(11, size * 0.36)
    }

    static func iconBubbleSize(compact: Bool) -> CGFloat {
        compact ? 31 : 35
    }
}

private struct WidgetGlassSurface: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let tint: Color
    let radius: CGFloat
    let fillOpacity: Double
    let glassTintOpacity: Double
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        let fullColor = renderingMode == .fullColor
        let resolvedTint = fullColor ? tint : WidgetTint.glass
        let contrastBoost = colorSchemeContrast == .increased ? 0.035 : 0
        let resolvedFillOpacity = fullColor ? min(fillOpacity + contrastBoost, 0.22) : min(fillOpacity, 0.065)
        let resolvedGlassOpacity = fullColor ? min(glassTintOpacity + contrastBoost, 0.26) : 0.04
        let resolvedStrokeOpacity = fullColor ? min(strokeOpacity + contrastBoost, 0.24) : 0.10

        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape
                    .fill(resolvedTint.opacity(resolvedFillOpacity))
                    .glassEffect(
                        .regular.tint(resolvedTint.opacity(resolvedGlassOpacity)),
                        in: shape
                    )
                    .overlay {
                        shape.stroke(.white.opacity(resolvedStrokeOpacity), lineWidth: 0.75)
                    }
                    .overlay {
                        shape.stroke(resolvedTint.opacity(fullColor ? 0.075 : 0.035), lineWidth: 0.55)
                    }
                    .shadow(color: resolvedTint.opacity(fullColor ? 0.045 : 0), radius: 8, x: 0, y: 4)
            }
    }
}

private enum WidgetTint {
    static let accent = Color(red: 0.05, green: 0.43, blue: 0.48)
    static let glass = Color(red: 0.25, green: 0.50, blue: 0.54)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.54)
}

private enum WidgetIconProminence {
    case decorative
    case status
    case action
}

private extension View {
    func widgetGlassSurface(
        tint: Color = WidgetTint.glass,
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
            policy: .after(Date().addingTimeInterval(MarketQuoteCache.widgetTimelineInterval))
        )
    }

    private func makeEntry(
        configuration: BuybackWidgetConfiguration,
        date: Date = .now
    ) async -> BuybackEntry {
        let query = configuration.symbol.trimmedForDisplay
        let directAsset = fallbackAsset(for: query)

        guard let client = MarketDataClientFactory.make() else {
            let cachedResult = MarketQuoteCache.cachedResult(for: directAsset, reason: "Missing API key", now: date)
            if let quote = cachedResult.quote {
                return makeQuotedEntry(
                    configuration: configuration,
                    date: date,
                    query: query,
                    asset: directAsset,
                    quote: quote,
                    priceStatus: widgetPriceStatus(for: cachedResult.status)
                )
            }

            return makeFallbackEntry(
                configuration: configuration,
                date: date,
                reason: "Missing API key",
                asset: directAsset
            )
        }

        do {
            let asset = try await resolveAsset(for: query, client: client)
            let quoteResult = await MarketQuoteCache.refreshQuote(for: asset, client: client, now: date)
            if let quote = quoteResult.quote {
                return makeQuotedEntry(
                    configuration: configuration,
                    date: date,
                    query: query,
                    asset: asset,
                    quote: quote,
                    priceStatus: widgetPriceStatus(for: quoteResult.status)
                )
            } else {
                return makeFallbackEntry(
                    configuration: configuration,
                    date: date,
                    reason: widgetFallbackReason(for: quoteResult.status),
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

    private func makeQuotedEntry(
        configuration: BuybackWidgetConfiguration,
        date: Date,
        query: String,
        asset: MarketAsset,
        quote: MarketQuote,
        priceStatus: WidgetPriceStatus
    ) -> BuybackEntry {
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
            priceStatus: priceStatus,
            alert: alert(for: asset.symbol),
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
            alert: alert(for: fallbackAsset.symbol),
            calculation: calculation
        )
    }

    private func alert(for symbol: String) -> PriceAlert? {
        PriceAlertStorage.load().first {
            $0.symbol == symbol.normalizedStockSymbol && $0.isEnabled
        }
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

struct BuybackPortfolioProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuybackPortfolioEntry {
        .preview
    }

    func snapshot(
        for configuration: BuybackPortfolioWidgetConfiguration,
        in context: Context
    ) async -> BuybackPortfolioEntry {
        .preview
    }

    func timeline(
        for configuration: BuybackPortfolioWidgetConfiguration,
        in context: Context
    ) async -> Timeline<BuybackPortfolioEntry> {
        let entry = await makeEntry(for: context)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(MarketQuoteCache.widgetTimelineInterval))
        )
    }

    private func makeEntry(for context: Context, date: Date = .now) async -> BuybackPortfolioEntry {
        let savedScenarios = SavedScenarioStorage.load()
        let pinnedScenarios = SavedScenarioStorage.pinnedScenarios(from: savedScenarios)
        let displayScenarios = SavedScenarioStorage.widgetScenarios(from: savedScenarios)
        guard !savedScenarios.isEmpty else {
            return BuybackPortfolioEntry(
                date: date,
                rows: [],
                hasSavedScenarios: false,
                hasPinnedScenarios: false,
                pinnedCount: 0
            )
        }

        let client = MarketDataClientFactory.make()
        let alerts = PriceAlertStorage.load()
        var rows: [BuybackPortfolioRow] = []
        for scenario in displayScenarios.prefix(maxRows(for: context.family)) {
            rows.append(await makeRow(for: scenario, client: client, alerts: alerts, date: date))
        }

        return BuybackPortfolioEntry(
            date: date,
            rows: rows,
            hasSavedScenarios: true,
            hasPinnedScenarios: !pinnedScenarios.isEmpty,
            pinnedCount: pinnedScenarios.count
        )
    }

    private func makeRow(
        for scenario: SavedBuybackScenario,
        client: CompositeMarketDataClient?,
        alerts: [PriceAlert],
        date: Date
    ) async -> BuybackPortfolioRow {
        let asset = scenario.portfolioAsset
        let quote: MarketQuote?
        let priceStatus: WidgetPriceStatus

        if let client {
            let result = await MarketQuoteCache.refreshQuote(for: asset, client: client, now: date)
            quote = result.quote
            priceStatus = widgetPriceStatus(for: result.status)
        } else {
            let result = MarketQuoteCache.cachedResult(for: asset, reason: "Missing key", now: date)
            quote = result.quote
            priceStatus = widgetPriceStatus(for: result.status)
        }

        let calculation = scenario.calculation(using: quote)

        return BuybackPortfolioRow(
            id: scenario.id,
            title: scenario.displayTitle,
            symbol: scenario.displaySymbol,
            assetName: scenario.selectedAsset?.name.trimmedForDisplay.nilIfEmpty,
            assetExchange: scenario.selectedAsset?.exchange.trimmedForDisplay.nilIfEmpty,
            quote: quote,
            priceStatus: priceStatus,
            alert: alerts.first { $0.symbol == scenario.displaySymbol && $0.isEnabled },
            calculation: calculation,
            trackingState: scenario.trackingState,
            frozenSellPrice: scenario.frozenSellPrice,
            currentMarketPrice: scenario.currentMarketPrice(using: quote),
            activeSellPrice: scenario.activeSellPrice(using: quote),
            isBuybackReady: scenario.isBuybackReady(using: quote)
        )
    }

    private func maxRows(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 2
        case .systemExtraLarge:
            return 10
        case .systemLarge:
            return 6
        default:
            return 3
        }
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
                CompactMetric(title: compactStatusTitle, value: compactStatusValue)
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
                MetricTile(title: "Price", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode), icon: .price, tint: WidgetTint.accent)
                MetricTile(title: "Gain", value: calculation.gainAtSellPercent.compactPercentString, icon: .percent, tint: WidgetTint.accent)
                MetricTile(title: statusTileTitle, value: statusTileValue, icon: statusTileIcon, tint: statusTileTint)
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
                tint: WidgetTint.accent,
                radius: WidgetMetrics.surfaceRadius(for: family),
                fillOpacity: 0.075,
                glassTintOpacity: 0.12,
                strokeOpacity: 0.13
            )

            DropBar(dropPercent: calculation.requiredDropPercent)

            Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 9) {
                GridRow {
                    MetricTile(title: "Price", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode), icon: .price, tint: WidgetTint.accent)
                    MetricTile(title: "Gain", value: calculation.gainAtSellPercent.compactPercentString, icon: .percent, tint: WidgetTint.accent)
                }

                GridRow {
                    MetricTile(title: "Basis", value: calculation.averageCostBasis.moneyString(currencyCode: calculation.currencyCode), icon: .basis, tint: WidgetTint.accent)
                    MetricTile(title: "Drop", value: calculation.requiredDropPercent.compactPercentString, icon: .drop, tint: WidgetTint.muted)
                }

                GridRow {
                    MetricTile(title: "Tax", value: calculation.taxAmount.moneyString(currencyCode: calculation.currencyCode), icon: .tax, tint: WidgetTint.accent)
                    MetricTile(title: statusTileTitle, value: statusTileValue, icon: statusTileIcon, tint: statusTileTint)
                }
            }
        }
    }

    private var compactStatusTitle: String {
        entry.alert?.isEnabled == true ? "Alert" : "Drop"
    }

    private var compactStatusValue: String {
        if let alert = entry.alert, alert.isEnabled {
            return alert.targetPrice.moneyString(currencyCode: alert.currencyCode)
        }
        return entry.calculation?.requiredDropPercent.compactPercentString ?? "-"
    }

    private var statusTileTitle: String {
        entry.alert?.isEnabled == true ? "Alert" : entry.priceStatus.label
    }

    private var statusTileValue: String {
        if let alert = entry.alert, alert.isEnabled {
            return alert.targetPrice.moneyString(currencyCode: alert.currencyCode)
        }
        return statusValue
    }

    private var statusTileIcon: BuybackIconKind {
        entry.alert?.isEnabled == true ? .alertArmed : entry.priceStatus.icon
    }

    private var statusTileTint: Color {
        entry.alert?.isEnabled == true ? WidgetTint.muted : statusTint
    }

    private var statusValue: String {
        switch entry.priceStatus {
        case .live:
            return entry.quote?.timestamp?.formatted(date: .omitted, time: .shortened) ?? "Now"
        case .cached(let reason):
            return reason
        case .fallback(let reason):
            return reason
        }
    }

    private var statusTint: Color {
        switch entry.priceStatus {
        case .live, .cached:
            return WidgetTint.accent
        case .fallback:
            return WidgetTint.muted
        }
    }

    private var invalidView: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            WidgetIconSurface(
                icon: .warning,
                tint: WidgetTint.muted,
                size: family == .systemSmall ? 31 : 36,
                prominence: .status
            )

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

struct BuybackPortfolioWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BuybackPortfolioEntry

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                emptyView
            } else {
                portfolioView
            }
        }
        .padding(WidgetMetrics.contentPadding(for: family))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            BuybackWidgetBackground()
        }
        .widgetURL(primaryDeepLinkURL)
    }

    private var portfolioView: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            PortfolioWidgetHeader(entry: entry)

            ForEach(entry.rows.prefix(maxRows)) { row in
                PortfolioAssetRow(row: row, compact: family == .systemSmall)
            }

            if family == .systemLarge {
                Spacer(minLength: 0)
                PortfolioWidgetFooter(entry: entry)
            }
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 11) {
            WidgetIconSurface(
                icon: .widget,
                tint: WidgetTint.accent,
                size: family == .systemSmall ? 30 : 36,
                prominence: .decorative
            )

            Text(entry.hasSavedScenarios ? "Pin assets" : "Save assets")
                .font(family == .systemSmall ? .headline.weight(.bold) : .title3.weight(.bold))
                .lineLimit(1)
                .widgetAccentable()

            Text(emptyMessage)
                .font(family == .systemSmall ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall:
            return 2
        case .systemExtraLarge:
            return 10
        case .systemLarge:
            return 6
        default:
            return 3
        }
    }

    private var emptyMessage: String {
        if entry.hasSavedScenarios {
            return "Pin up to \(SavedScenarioStorage.maximumPinnedScenarios) saved scenarios in the app to track prices and buy-back limits here."
        }

        return "Save a buy-back scenario in the app, then pin it for the portfolio widget."
    }

    private var primaryDeepLinkURL: URL? {
        guard let row = entry.rows.first,
              let calculation = row.calculation
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "buybackcalculator"
        components.host = "calculator"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: row.symbol),
            URLQueryItem(name: "price", value: calculation.sellPrice.inputString),
            URLQueryItem(name: "gain", value: calculation.gainAtSellPercent.inputString),
            URLQueryItem(name: "taxProfile", value: calculation.taxProfile.rawValue),
            URLQueryItem(name: "taxRate", value: calculation.taxRatePercent.inputString),
            URLQueryItem(name: "taxCurrency", value: calculation.taxCurrencyCode),
            URLQueryItem(name: "fxRate", value: calculation.fxRateToTaxCurrency.inputString)
        ]
        return components.url
    }
}

private struct PortfolioWidgetHeader: View {
    @Environment(\.widgetFamily) private var family

    let entry: BuybackPortfolioEntry

    var body: some View {
        HStack(spacing: 9) {
            WidgetIconSurface(
                icon: .asset,
                tint: WidgetTint.accent,
                size: family == .systemSmall ? 29 : 33,
                prominence: .decorative
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.hasPinnedScenarios ? "Pinned Assets" : "Portfolio")
                    .font(family == .systemSmall ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()

                if family != .systemSmall {
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(entry.date, style: .time)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        let readyCount = entry.rows.filter(\.isBuybackReady).count
        let liveCount = entry.rows.filter {
            switch $0.priceStatus {
            case .live, .cached:
                return true
            case .fallback:
                return false
            }
        }.count
        let frozenCount = entry.rows.filter { $0.trackingState == .frozen }.count
        let alertCount = entry.rows.filter { $0.alert?.isEnabled == true }.count
        if readyCount > 0 {
            return "\(readyCount) ready / \(entry.rows.count)"
        }
        if entry.hasPinnedScenarios {
            let trackedText = "\(entry.pinnedCount) pinned"
            if liveCount > 0 {
                return "\(liveCount) priced / \(trackedText)"
            }
            return alertCount > 0 ? "\(trackedText) / \(alertCount) alerts" : trackedText
        }
        if frozenCount > 0 {
            return "\(frozenCount) frozen / \(entry.rows.count)"
        }
        guard liveCount > 0 else {
            return alertCount > 0 ? "Saved prices / \(alertCount) alerts" : "Saved prices"
        }
        let liveText = "\(liveCount) live / \(entry.rows.count)"
        return alertCount > 0 ? "\(liveText) / \(alertCount) alerts" : liveText
    }
}

private struct PortfolioAssetRow: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let row: BuybackPortfolioRow
    let compact: Bool

    private var tint: Color {
        if row.isBuybackReady {
            return WidgetTint.accent
        }

        if row.trackingState == .frozen {
            return WidgetTint.muted
        }

        switch row.priceStatus {
        case .live, .cached:
            return WidgetTint.accent
        case .fallback:
            return WidgetTint.muted
        }
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            WidgetIconSurface(
                icon: rowIcon,
                tint: tint,
                size: compact ? 29 : 33,
                prominence: .status
            )

            VStack(alignment: .leading, spacing: compact ? 0 : 1) {
                Text(row.symbol)
                    .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !compact, let descriptor {
                    Text(descriptor)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 4)

            if let freezeIntent {
                Button(intent: freezeIntent) {
                    WidgetIconSurface(
                        icon: .bookmark,
                        tint: WidgetTint.muted,
                        size: compact ? 29 : 32,
                        prominence: .action
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Freeze \(row.symbol)")
            }

            if let calculation = row.calculation {
                VStack(alignment: .trailing, spacing: compact ? 0 : 1) {
                    Text(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode))
                        .font((compact ? Font.caption : Font.callout).monospacedDigit().weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(compact ? 0.54 : 0.62)
                        .widgetAccentable()

                    Text(secondaryValue(for: calculation))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
            } else {
                Text("Check")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 8)
        .widgetGlassSurface(
            tint: tint,
            radius: WidgetMetrics.surfaceRadius(for: family),
            fillOpacity: renderingMode == .fullColor ? 0.085 : 0.052,
            glassTintOpacity: renderingMode == .fullColor ? 0.10 : 0.035,
            strokeOpacity: renderingMode == .fullColor ? 0.12 : 0.08
        )
    }

    private var rowIcon: BuybackIconKind {
        if row.isBuybackReady {
            return .selected
        }

        if row.trackingState == .frozen {
            return .bookmark
        }

        return row.priceStatus.icon
    }

    private var freezeIntent: FreezeScenarioIntent? {
        guard row.trackingState == .watching,
              let quote = row.quote,
              quote.price.isFinite,
              quote.price > 0
        else {
            return nil
        }

        return FreezeScenarioIntent(
            scenarioID: row.id.uuidString,
            sellPrice: quote.price,
            currencyCode: quote.currencyCode,
            quoteUnixTime: quote.timestamp?.timeIntervalSince1970 ?? 0
        )
    }

    private var descriptor: String? {
        let cleanedTitle = row.title.trimmedForDisplay
        let title = cleanedTitle.caseInsensitiveCompare(row.symbol) == .orderedSame ? nil : cleanedTitle.nilIfEmpty
        let exchange = row.assetExchange?.trimmedForDisplay.nilIfEmpty

        switch (title, exchange) {
        case (.some(let title), .some(let exchange)):
            return "\(title) - \(exchange)"
        case (.some(let title), .none):
            return title
        case (.none, .some(let exchange)):
            return exchange
        case (.none, .none):
            return nil
        }
    }

    private func secondaryValue(for calculation: BuybackCalculation) -> String {
        if row.isBuybackReady {
            return "Ready"
        }

        if row.trackingState == .frozen {
            if let currentMarketPrice = row.currentMarketPrice {
                let currencyCode = row.quote?.currencyCode ?? calculation.currencyCode
                return "Now \(currentMarketPrice.moneyString(currencyCode: currencyCode))"
            }

            if let frozenSellPrice = row.frozenSellPrice {
                return "Frozen \(frozenSellPrice.moneyString(currencyCode: calculation.currencyCode))"
            }
        }

        if let alert = row.alert, alert.isEnabled {
            return "Alert \(alert.targetPrice.moneyString(currencyCode: alert.currencyCode))"
        }

        return "Price \(calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode))"
    }
}

private struct PortfolioWidgetFooter: View {
    let entry: BuybackPortfolioEntry

    var body: some View {
        HStack(spacing: 6) {
            WidgetIconSurface(icon: .live, tint: WidgetTint.muted, size: 20, prominence: .decorative)

            Text("Quotes refresh at most every 15 min; cache protects API limits")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetIconSurface: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let icon: BuybackIconKind
    let tint: Color
    let size: CGFloat
    let prominence: WidgetIconProminence

    var body: some View {
        let fullColor = renderingMode == .fullColor
        let contrastBoost = colorSchemeContrast == .increased ? 0.045 : 0
        let resolvedTint = fullColor ? tint : WidgetTint.glass
        let fillOpacity = min(baseFillOpacity + contrastBoost, 0.34)
        let glassOpacity = min(baseGlassOpacity + contrastBoost, 0.34)
        let shape = RoundedRectangle(cornerRadius: WidgetMetrics.iconSurfaceRadius(for: size), style: .continuous)

        BuybackIcon(icon, tint: fullColor ? .white : .primary)
            .frame(width: size * glyphScale, height: size * glyphScale)
            .shadow(color: .black.opacity(fullColor ? 0.22 : 0), radius: 1, x: 0, y: 0.7)
            .widgetAccentable()
            .frame(width: size, height: size)
            .background {
                shape
                    .fill(resolvedTint.opacity(fillOpacity))
                    .glassEffect(.regular.tint(resolvedTint.opacity(glassOpacity)), in: shape)
                    .overlay {
                        shape.stroke(.white.opacity(fullColor ? 0.24 : 0.10), lineWidth: 0.8)
                    }
                    .overlay {
                        shape.stroke(resolvedTint.opacity(fullColor ? 0.12 : 0.04), lineWidth: 0.55)
                    }
                    .shadow(color: resolvedTint.opacity(fullColor ? shadowOpacity : 0), radius: 10, x: 0, y: 5)
            }
    }

    private var glyphScale: CGFloat {
        switch prominence {
        case .decorative:
            return 0.56
        case .status:
            return 0.58
        case .action:
            return 0.54
        }
    }

    private var baseFillOpacity: Double {
        switch prominence {
        case .decorative:
            return 0.16
        case .status:
            return 0.22
        case .action:
            return 0.26
        }
    }

    private var baseGlassOpacity: Double {
        switch prominence {
        case .decorative:
            return 0.15
        case .status:
            return 0.19
        case .action:
            return 0.23
        }
    }

    private var shadowOpacity: Double {
        switch prominence {
        case .decorative:
            return 0.045
        case .status:
            return 0.060
        case .action:
            return 0.075
        }
    }
}

private struct WidgetHeader: View {
    let entry: BuybackEntry
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            WidgetIconSurface(
                icon: entry.priceStatus.icon,
                tint: statusTint,
                size: WidgetMetrics.iconBubbleSize(compact: compact),
                prominence: .status
            )

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
        case .live, .cached:
            return WidgetTint.accent
        case .fallback:
            return WidgetTint.muted
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
        case .live, .cached:
            return WidgetTint.accent
        case .fallback:
            return WidgetTint.muted
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

    private var fillColor: Color { WidgetTint.accent }

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
                        .fill(WidgetTint.muted.opacity(0.16))
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
                    WidgetTint.glass.opacity(0.040),
                    WidgetTint.muted.opacity(0.026),
                    WidgetTint.glass.opacity(0.020),
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

struct BuybackPortfolioWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: BuybackWidgetKind.portfolio,
            intent: BuybackPortfolioWidgetConfiguration.self,
            provider: BuybackPortfolioProvider()
        ) { entry in
            BuybackPortfolioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Buy-Back Portfolio")
        .description("Displays pinned assets with cached live prices and calculated buy-back limits when Finnhub is available.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
        .supportedMountingStyles([.elevated, .recessed])
    }
}

private enum BuybackWidgetKind {
    static let value = "BuybackWidget"
    static let portfolio = "BuybackPortfolioWidget"
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
        alert: PriceAlert(symbol: "AAPL", targetPrice: 140, currencyCode: "USD", isEnabled: true, lastTriggeredAt: nil),
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
        alert: nil,
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
        alert: nil,
        calculation: nil
    )
}

private extension BuybackPortfolioEntry {
    static let preview = BuybackPortfolioEntry(
        date: .now,
        rows: [
            BuybackPortfolioRow(
                id: UUID(uuidString: "A73406C4-19AB-4CC8-B441-86F780F2C96D") ?? UUID(),
                title: "Apple Inc.",
                symbol: "AAPL",
                assetName: "Apple Inc.",
                assetExchange: "US",
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
                alert: PriceAlert(symbol: "AAPL", targetPrice: 140, currencyCode: "USD", isEnabled: true, lastTriggeredAt: nil),
                calculation: BuybackCalculator.calculate(
                    symbol: "AAPL",
                    sellPrice: 185,
                    gainAtSellPercent: 463.10
                ),
                trackingState: .watching,
                frozenSellPrice: nil,
                currentMarketPrice: 185,
                activeSellPrice: 185,
                isBuybackReady: false
            ),
            BuybackPortfolioRow(
                id: UUID(uuidString: "B8612D95-6E3D-46C0-94B4-48FAF1FD71EC") ?? UUID(),
                title: "Microsoft",
                symbol: "MSFT",
                assetName: "Microsoft",
                assetExchange: "US",
                quote: MarketQuote(
                    symbol: "MSFT",
                    price: 300,
                    currencyCode: "USD",
                    timestamp: .now,
                    source: .finnhub,
                    isStale: false,
                    statusMessage: nil
                ),
                priceStatus: .live,
                alert: nil,
                calculation: BuybackCalculator.calculate(
                    symbol: "MSFT",
                    sellPrice: 430,
                    gainAtSellPercent: 155
                ),
                trackingState: .frozen,
                frozenSellPrice: 430,
                currentMarketPrice: 300,
                activeSellPrice: 430,
                isBuybackReady: true
            ),
            BuybackPortfolioRow(
                id: UUID(uuidString: "B92D86F8-6C2B-4D2C-8E42-34DD2F7B27AA") ?? UUID(),
                title: "SAP",
                symbol: "SAP.DE",
                assetName: "SAP SE",
                assetExchange: "Germany",
                quote: nil,
                priceStatus: .fallback("Saved price"),
                alert: PriceAlert(symbol: "SAP.DE", targetPrice: 210, currencyCode: "EUR", isEnabled: true, lastTriggeredAt: nil),
                calculation: BuybackCalculator.calculate(
                    symbol: "SAP.DE",
                    sellPrice: 240,
                    gainAtSellPercent: 82,
                    currencyCode: "EUR"
                ),
                trackingState: .watching,
                frozenSellPrice: nil,
                currentMarketPrice: nil,
                activeSellPrice: 240,
                isBuybackReady: false
            )
        ],
        hasSavedScenarios: true,
        hasPinnedScenarios: true,
        pinnedCount: 3
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

#Preview("Portfolio Medium", as: .systemMedium) {
    BuybackPortfolioWidget()
} timeline: {
    BuybackPortfolioEntry.preview
}

#Preview("Portfolio Large", as: .systemLarge) {
    BuybackPortfolioWidget()
} timeline: {
    BuybackPortfolioEntry.preview
}
