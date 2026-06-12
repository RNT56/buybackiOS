import SwiftUI
import WidgetKit

struct ContentView: View {
    @AppStorage("buybackCalculator.assetQuery") private var assetQuery = BuybackCalculator.defaultSymbol
    @AppStorage("buybackCalculator.selectedAsset") private var selectedAssetData = ""
    @AppStorage("buybackCalculator.symbol") private var symbolText = BuybackCalculator.defaultSymbol
    @AppStorage("buybackCalculator.sellPrice") private var sellPriceText = BuybackCalculator.defaultSellPrice.inputString
    @AppStorage("buybackCalculator.gainPercent") private var gainPercentText = "463.10"
    @AppStorage("buybackCalculator.shares") private var sharesText = "1"
    @AppStorage("buybackCalculator.taxRate") private var taxRateText = BuybackCalculator.fixedTaxRatePercent.inputString
    @AppStorage("buybackCalculator.targetExtra") private var targetExtraText = BuybackCalculator.fixedTargetExtraSharesPercent.inputString

    @StateObject private var lookup = MarketLookupViewModel()
    @StateObject private var apiKeys = APIKeySettingsViewModel()
    @State private var manualPriceEnabled = false
    @State private var advancedExpanded = false
    @State private var apiKeysExpanded = false
    @FocusState private var focusedField: CalculatorField?

    private var activeSymbol: String {
        lookup.selectedAsset?.symbol.nilIfBlank ?? symbolText.normalizedStockSymbol.nilIfBlank ?? assetQuery.normalizedStockSymbol
    }

    private var activeCurrencyCode: String {
        lookup.quote?.currencyCode ?? lookup.selectedAsset?.currencyCode ?? BuybackCalculator.defaultCurrencyCode
    }

    private var sellPrice: Double? {
        BuybackCalculator.parseDecimal(sellPriceText)
    }

    private var gainPercent: Double? {
        BuybackCalculator.parseDecimal(gainPercentText)
    }

    private var sharesToSell: Double? {
        BuybackCalculator.parseDecimal(sharesText)
    }

    private var taxRatePercent: Double? {
        BuybackCalculator.parseDecimal(taxRateText)
    }

    private var targetExtraSharesPercent: Double? {
        BuybackCalculator.parseDecimal(targetExtraText)
    }

    private var calculation: BuybackCalculation? {
        guard let sellPrice,
              let gainPercent,
              let sharesToSell,
              let taxRatePercent,
              let targetExtraSharesPercent
        else {
            return nil
        }

        return BuybackCalculator.calculate(
            symbol: activeSymbol,
            sellPrice: sellPrice,
            gainAtSellPercent: gainPercent,
            sharesToSell: sharesToSell,
            taxRatePercent: taxRatePercent,
            targetExtraSharesPercent: targetExtraSharesPercent,
            currencyCode: activeCurrencyCode
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    lookupPanel
                    apiKeyPanel
                    inputPanel

                    if let calculation {
                        resultSummary(calculation)
                        positionBreakdown(calculation)
                        sensitivitySection(calculation)
                    } else {
                        invalidState
                    }

                    widgetStatus
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background {
                LiquidGlassBackground()
                .ignoresSafeArea()
                .backgroundExtensionEffect()
            }
            .navigationTitle("Buy-Back")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshSelectedQuote()
                    } label: {
                        Label("Refresh Price", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(lookup.selectedAsset == nil || lookup.isFetchingQuote)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
        .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
        .task {
            configureLookupClient()
            apiKeysExpanded = !apiKeys.hasUsableFinnhubAPIKey
            restoreSelectionIfNeeded()
            lookup.scheduleSearch(query: assetQuery)
        }
        .onChange(of: assetQuery) { _, newValue in
            if newValue.normalizedStockSymbol != lookup.selectedAsset?.symbol {
                lookup.clearSelection()
                selectedAssetData = ""
                symbolText = newValue.normalizedStockSymbol
            }
            lookup.scheduleSearch(query: newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                LiquidGlassIcon(systemImage: "arrow.triangle.2.circlepath", tint: .teal, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)

                    Text(activeSymbol.isEmpty ? "buy-back" : "\(activeSymbol) buy-back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                GlassBadge(title: "Price", value: sellPrice.map { $0.moneyString(currencyCode: activeCurrencyCode) } ?? "Missing")
                GlassBadge(title: "Tax", value: parsedText(taxRateText) + "%")
                GlassBadge(title: "Target", value: "+" + parsedText(targetExtraText) + "%")
            }
        }
    }

    private var lookupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Asset", systemImage: "magnifyingglass")

            VStack(alignment: .leading, spacing: 8) {
                Label("Name, ticker, ISIN, or WKN", systemImage: "textformat.characters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("AAPL, Apple, US0378331005", text: $assetQuery)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .asset)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 52)
                    .liquidFieldSurface(isFocused: focusedField == .asset)
            }

            if lookup.isSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching assets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .liquidCapsuleSurface(tint: LiquidPalette.blue)
            } else if !lookup.suggestions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(lookup.suggestions) { asset in
                        Button {
                            select(asset)
                        } label: {
                            AssetSuggestionRow(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let message = lookup.message {
                StatusRow(message: message)
            }

            if let selectedAsset = lookup.selectedAsset {
                SelectedAssetRow(asset: selectedAsset, quote: lookup.quote)
            }
        }
        .liquidSurface()
    }

    private var apiKeyPanel: some View {
        DisclosureGroup(isExpanded: $apiKeysExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Finnhub", systemImage: "bolt.horizontal.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    SecureField("Required for live search and quotes", text: $apiKeys.finnhubAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .finnhubKey)
                        .font(.body.monospaced())
                        .padding(.horizontal, 13)
                        .frame(height: 50)
                        .liquidFieldSurface(isFocused: focusedField == .finnhubKey)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("OpenFIGI", systemImage: "key.horizontal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    SecureField("Optional for higher identifier-map limits", text: $apiKeys.openFIGIAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .openFIGIKey)
                        .font(.body.monospaced())
                        .padding(.horizontal, 13)
                        .frame(height: 50)
                        .liquidFieldSurface(isFocused: focusedField == .openFIGIKey)
                }

                HStack(spacing: 10) {
                    Button {
                        apiKeys.save()
                        configureLookupClient()
                        lookup.scheduleSearch(query: assetQuery)
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button(role: .destructive) {
                        apiKeys.clear()
                        configureLookupClient()
                        lookup.scheduleSearch(query: assetQuery)
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }

                StatusRow(message: apiKeyStatusMessage)
            }
            .padding(.top, 12)
        } label: {
            SectionTitle("API Keys", systemImage: apiKeys.hasUsableFinnhubAPIKey ? "key.fill" : "key")
        }
        .liquidSurface()
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Calculator", systemImage: "number")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                decimalField(
                    "Current price",
                    text: $sellPriceText,
                    suffix: activeCurrencyCode,
                    icon: lookup.quote == nil || manualPriceEnabled ? "pencil" : "bolt.fill",
                    field: .price,
                    isDisabled: lookup.quote != nil && !manualPriceEnabled
                )

                decimalField(
                    "Current gain",
                    text: $gainPercentText,
                    suffix: "%",
                    icon: "percent",
                    field: .gain,
                    keyboardType: .numbersAndPunctuation
                )
            }

            if lookup.isFetchingQuote {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching latest price")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .liquidCapsuleSurface(tint: LiquidPalette.accent)
            } else if let quote = lookup.quote {
                QuoteStatusRow(quote: quote, manualPriceEnabled: manualPriceEnabled)
            }

            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $manualPriceEnabled) {
                        Label("Manual price override", systemImage: "pencil.and.list.clipboard")
                            .font(.subheadline.weight(.semibold))
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        decimalField("Shares", text: $sharesText, suffix: "sh", icon: "number", field: .shares)
                        decimalField("Tax rate", text: $taxRateText, suffix: "%", icon: "building.columns", field: .taxRate)
                    }

                    decimalField(
                        "Extra shares target",
                        text: $targetExtraText,
                        suffix: "%",
                        icon: "arrow.up.forward.circle",
                        field: .targetExtra
                    )

                    Button {
                        refreshSelectedQuote()
                    } label: {
                        Label("Refresh selected price", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(lookup.selectedAsset == nil || lookup.isFetchingQuote)
                }
                .padding(.top, 12)
            } label: {
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
        }
        .liquidSurface()
    }

    private func decimalField(
        _ title: String,
        text: Binding<String>,
        suffix: String,
        icon: String,
        field: CalculatorField,
        keyboardType: UIKeyboardType = .decimalPad,
        isDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            HStack(spacing: 8) {
                TextField(title, text: text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .disabled(isDisabled)

                Text(suffix)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            .liquidFieldSurface(isFocused: focusedField == field, isDisabled: isDisabled)
        }
    }

    private func resultSummary(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                SectionTitle("Buy-back limit", systemImage: "scope")
                Spacer(minLength: 8)
                Text(lookup.quote == nil || manualPriceEnabled ? "Manual" : "Auto")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidCapsuleSurface(tint: LiquidPalette.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(calculation.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DropGauge(dropPercent: calculation.requiredDropPercent)
        }
        .liquidSurface(prominent: true)
    }

    private func positionBreakdown(_ calculation: BuybackCalculation) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            MetricTile(title: "Required drop", value: calculation.requiredDropPercent.percentString, systemImage: "arrow.down.right")
            MetricTile(title: "Gain", value: calculation.gainAtSellPercent.percentString, systemImage: "percent")
            MetricTile(title: "Cost basis", value: calculation.averageCostBasis.moneyString(currencyCode: calculation.currencyCode), systemImage: "banknote")
            MetricTile(title: "After-tax cash", value: calculation.afterTaxCash.moneyString(currencyCode: calculation.currencyCode), systemImage: "creditcard")
            MetricTile(title: "Tax estimate", value: calculation.taxAmount.moneyString(currencyCode: calculation.currencyCode), systemImage: "building.columns")
            MetricTile(title: "Target shares", value: calculation.targetShareCount.shareString, systemImage: "plus.forwardslash.minus")
        }
    }

    private func sensitivitySection(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Price sensitivity", systemImage: "slider.horizontal.3")

            VStack(spacing: 8) {
                ForEach(sensitivityRows(for: calculation)) { row in
                    HStack(spacing: 10) {
                        Text(row.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(row.isBase ? Color.accentColor : Color.secondary)
                            .frame(width: 48, alignment: .leading)

                        Text(row.sellPrice.moneyString(currencyCode: calculation.currencyCode))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(row.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode))
                                .font(.subheadline.monospacedDigit().weight(.bold))
                            Text(row.requiredDropPercent.compactPercentString + " drop")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .liquidCardBackground(tint: row.isBase ? LiquidPalette.accent.opacity(0.34) : LiquidPalette.blue.opacity(0.16))
                }
            }
        }
        .liquidSurface()
    }

    private var invalidState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                LiquidGlassIcon(systemImage: "exclamationmark.triangle.fill", tint: .orange, size: 34)

                Text("Check inputs")
                    .font(.headline)
            }

            Text(validationMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidSurface()
    }

    private var widgetStatus: some View {
        HStack(spacing: 12) {
            LiquidGlassIcon(systemImage: "rectangle.on.rectangle.angled", tint: LiquidPalette.blue, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Home Screen widget")
                    .font(.headline)
                Text("Configure symbol, gain, and fallback price. The widget refreshes live quotes when available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                WidgetCenter.shared.reloadAllTimelines()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Reload widgets")
        }
        .liquidSurface()
    }

    private var displayName: String {
        lookup.selectedAsset?.name.nilIfBlank ?? activeSymbol
    }

    private var apiKeyStatusMessage: LookupMessage {
        if let statusMessage = apiKeys.statusMessage {
            return .info(statusMessage)
        }

        if apiKeys.hasRuntimeFinnhubAPIKey {
            return .info("Using the Finnhub key saved on this device.")
        }

        if apiKeys.hasBundledFinnhubAPIKey {
            return .info("Using the Finnhub key bundled with the app build.")
        }

        return .warning("Live autocomplete and prices need a Finnhub key.")
    }

    private var validationMessage: String {
        guard let sellPrice else {
            return "Enter a current price above 0."
        }

        guard sellPrice > 0 else {
            return "Current price must be above 0."
        }

        guard let gainPercent else {
            return "Enter a numeric gain percentage."
        }

        guard gainPercent > -100 else {
            return "Gain must be greater than -100%."
        }

        guard let sharesToSell, sharesToSell > 0 else {
            return "Shares must be greater than 0."
        }

        guard let taxRatePercent, taxRatePercent >= 0, taxRatePercent <= 100 else {
            return "Tax rate must be between 0% and 100%."
        }

        guard let targetExtraSharesPercent, targetExtraSharesPercent >= 0 else {
            return "Target extra shares must be 0% or higher."
        }

        return "Enter a selected asset, current price, and gain."
    }

    private func sensitivityRows(for calculation: BuybackCalculation) -> [SensitivityRow] {
        [-0.05, -0.02, 0, 0.02, 0.05].compactMap { movement in
            let sellPrice = calculation.sellPrice * (1 + movement)

            guard let variant = BuybackCalculator.calculate(
                symbol: calculation.symbol,
                sellPrice: sellPrice,
                gainAtSellPercent: calculation.gainAtSellPercent,
                sharesToSell: calculation.sharesToSell,
                taxRatePercent: calculation.taxRatePercent,
                targetExtraSharesPercent: calculation.targetExtraSharesPercent,
                currencyCode: calculation.currencyCode
            ) else {
                return nil
            }

            return SensitivityRow(
                id: movement.key,
                label: movement == 0 ? "Base" : movement.compactPercentString,
                sellPrice: sellPrice,
                maximumBuybackPrice: variant.maximumBuybackPrice,
                requiredDropPercent: variant.requiredDropPercent,
                isBase: movement == 0
            )
        }
    }

    private func select(_ asset: MarketAsset) {
        lookup.prepareSelection(asset)
        assetQuery = asset.symbol
        symbolText = asset.symbol
        persist(asset)
        focusedField = nil

        Task {
            if let quote = await lookup.fetchQuote(for: asset) {
                sellPriceText = quote.price.inputString
                manualPriceEnabled = false
            } else {
                manualPriceEnabled = true
            }
        }
    }

    private func refreshSelectedQuote() {
        guard let selectedAsset = lookup.selectedAsset else { return }
        Task {
            if let quote = await lookup.fetchQuote(for: selectedAsset) {
                sellPriceText = quote.price.inputString
                manualPriceEnabled = false
            } else {
                manualPriceEnabled = true
            }
        }
    }

    private func restoreSelectionIfNeeded() {
        guard lookup.selectedAsset == nil,
              let data = selectedAssetData.data(using: .utf8),
              let asset = try? JSONDecoder().decode(MarketAsset.self, from: data)
        else {
            return
        }
        lookup.restoreSelection(asset)
        assetQuery = asset.symbol
        symbolText = asset.symbol
    }

    private func persist(_ asset: MarketAsset) {
        guard let data = try? JSONEncoder().encode(asset),
              let string = String(data: data, encoding: .utf8)
        else {
            return
        }
        selectedAssetData = string
    }

    private func configureLookupClient() {
        lookup.configure(
            finnhubAPIKey: apiKeys.effectiveFinnhubAPIKey,
            openFIGIAPIKey: apiKeys.effectiveOpenFIGIAPIKey
        )
    }

    private func parsedText(_ text: String) -> String {
        BuybackCalculator.parseDecimal(text)?.inputString ?? text
    }
}

@MainActor
private final class MarketLookupViewModel: ObservableObject {
    @Published var suggestions: [MarketAsset] = []
    @Published var selectedAsset: MarketAsset?
    @Published var quote: MarketQuote?
    @Published var message: LookupMessage?
    @Published var isSearching = false
    @Published var isFetchingQuote = false

    private var client = MarketDataClientFactory.make()
    private var searchCache: [String: [MarketAsset]] = [:]
    private var quoteCache: [String: CachedQuote] = [:]
    private var searchTask: Task<Void, Never>?
    private var quoteTask: Task<Void, Never>?

    func configure(finnhubAPIKey: String?, openFIGIAPIKey: String?) {
        client = MarketDataClientFactory.make(
            finnhubAPIKey: finnhubAPIKey,
            openFIGIAPIKey: openFIGIAPIKey
        )
        searchTask?.cancel()
        quoteTask?.cancel()
        searchCache.removeAll(keepingCapacity: true)
        quoteCache.removeAll(keepingCapacity: true)
        isSearching = false
        isFetchingQuote = false
    }

    func scheduleSearch(query: String) {
        searchTask?.cancel()

        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = cleanedQuery.uppercased()
        guard cleanedQuery.count >= 2 else {
            suggestions = []
            message = nil
            isSearching = false
            return
        }

        guard cleanedQuery.normalizedStockSymbol != selectedAsset?.symbol else {
            suggestions = []
            isSearching = false
            return
        }

        if let cachedResults = searchCache[cacheKey] {
            suggestions = cachedResults
            isSearching = false
            message = cachedResults.isEmpty ? .info("No matching assets found.") : nil
            return
        }

        guard let client else {
            suggestions = []
            isSearching = false
            message = .warning("Add FINNHUB_API_KEY in Config/Secrets.xcconfig to enable autocomplete and live prices.")
            return
        }

        isSearching = true
        message = nil

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                let results = try await client.searchAssets(query: cleanedQuery)
                guard !Task.isCancelled else { return }
                self?.applySearchResults(results, cacheKey: cacheKey)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applySearchError(error)
            }
        }
    }

    func prepareSelection(_ asset: MarketAsset) {
        selectedAsset = asset
        suggestions = []
        message = nil
        quote = nil
    }

    func restoreSelection(_ asset: MarketAsset) {
        selectedAsset = asset
    }

    func clearSelection() {
        selectedAsset = nil
        quote = nil
    }

    func fetchQuote(for asset: MarketAsset) async -> MarketQuote? {
        quoteTask?.cancel()
        let cacheKey = asset.id
        if let cached = quoteCache[cacheKey], cached.isFresh {
            selectedAsset = asset
            quote = cached.quote
            message = nil
            return cached.quote
        }

        guard let client else {
            quote = nil
            message = .warning("Live quote unavailable until FINNHUB_API_KEY is configured.")
            return nil
        }

        selectedAsset = asset
        isFetchingQuote = true
        message = nil

        do {
            let quote = try await client.quote(for: asset)
            self.quote = quote
            quoteCache[cacheKey] = CachedQuote(quote: quote, storedAt: .now)
            isFetchingQuote = false
            return quote
        } catch {
            self.quote = nil
            isFetchingQuote = false
            message = .warning(message(for: error))
            return nil
        }
    }

    private func applySearchResults(_ results: [MarketAsset], cacheKey: String) {
        searchCache[cacheKey] = results
        suggestions = results
        isSearching = false
        message = results.isEmpty ? .info("No matching assets found.") : nil
    }

    private func applySearchError(_ error: Error) {
        suggestions = []
        isSearching = false
        message = .warning(message(for: error))
    }

    private func message(for error: Error) -> String {
        if let marketDataError = error as? MarketDataError {
            return marketDataError.localizedDescription
        }
        return "Market-data request failed. Enter the price manually."
    }

    private struct CachedQuote {
        let quote: MarketQuote
        let storedAt: Date

        var isFresh: Bool {
            abs(storedAt.timeIntervalSinceNow) < 60
        }
    }
}

private enum CalculatorField: Hashable {
    case asset
    case price
    case gain
    case shares
    case taxRate
    case targetExtra
    case finnhubKey
    case openFIGIKey
}

private struct LookupMessage: Equatable {
    enum Style {
        case info
        case warning
    }

    let text: String
    let style: Style

    static func info(_ text: String) -> LookupMessage {
        LookupMessage(text: text, style: .info)
    }

    static func warning(_ text: String) -> LookupMessage {
        LookupMessage(text: text, style: .warning)
    }
}

private struct SensitivityRow: Identifiable {
    let id: String
    let label: String
    let sellPrice: Double
    let maximumBuybackPrice: Double
    let requiredDropPercent: Double
    let isBase: Bool
}

private struct AssetSuggestionRow: View {
    let asset: MarketAsset

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiquidGlassIcon(systemImage: "chart.line.uptrend.xyaxis", tint: LiquidPalette.blue, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name.nilIfBlank ?? asset.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(asset.symbol)
                    Text(asset.exchange.nilIfBlank ?? "Global")
                    Text(asset.currencyCode)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.blue.opacity(0.22))
    }
}

private struct SelectedAssetRow: View {
    let asset: MarketAsset
    let quote: MarketQuote?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LiquidGlassIcon(
                systemImage: quote == nil ? "checkmark.circle" : "bolt.circle.fill",
                tint: quote == nil ? .secondary : LiquidPalette.accent,
                size: 34
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.symbol)
                    .font(.headline.monospaced())
                    .lineLimit(1)

                Text([asset.name, asset.exchange, asset.currencyCode].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.32))
    }
}

private struct QuoteStatusRow: View {
    let quote: MarketQuote
    let manualPriceEnabled: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: manualPriceEnabled ? "pencil.circle" : "bolt.circle.fill")
                .foregroundStyle(manualPriceEnabled ? Color.orange : Color.accentColor)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidCapsuleSurface(tint: manualPriceEnabled ? .orange : LiquidPalette.accent)
    }

    private var statusText: String {
        let source = "\(quote.source.rawValue) price"
        let timestamp = quote.timestamp.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        }
        let timestampText = timestamp.map { "updated \($0)" } ?? "timestamp unavailable"
        let overrideText = manualPriceEnabled ? "Manual override is active." : "Auto-filled current price."
        return "\(source), \(timestampText). \(overrideText)"
    }
}

private struct StatusRow: View {
    let message: LookupMessage

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: message.style == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(message.style == .warning ? .orange : .secondary)

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidCapsuleSurface(tint: message.style == .warning ? .orange : LiquidPalette.blue)
    }
}

private enum LiquidPalette {
    static let accent = Color(red: 0.02, green: 0.66, blue: 0.62)
    static let blue = Color(red: 0.20, green: 0.38, blue: 0.90)
    static let amber = Color(red: 0.90, green: 0.58, blue: 0.18)
    static let ink = Color(red: 0.02, green: 0.08, blue: 0.10)
}

private struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

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

private struct SectionTitle: View {
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

private struct LiquidGlassIcon: View {
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

private struct GlassBadge: View {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidCapsuleSurface(tint: LiquidPalette.accent.opacity(0.55))
    }
}

private struct MetricTile: View {
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

private struct DropGauge: View {
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
    let tint: Color
    var prominent = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .background {
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

private struct LiquidFieldSurface: ViewModifier {
    let isFocused: Bool
    let isDisabled: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .background {
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

private struct LiquidCapsuleSurface: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .background {
                shape
                    .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.48))
                    .glassEffect(.regular.tint(tint.opacity(0.30)), in: shape)
                    .overlay {
                        shape.stroke(.white.opacity(0.18), lineWidth: 0.7)
                    }
            }
    }
}

private extension View {
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Double {
    var key: String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

#Preview("Lookup") {
    ContentView()
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
