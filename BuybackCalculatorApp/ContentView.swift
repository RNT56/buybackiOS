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
    @AppStorage("buybackCalculator.sellFee") private var sellFeeText = BuybackCalculator.defaultSellFeeTotal.inputString
    @AppStorage("buybackCalculator.buyFee") private var buyFeeText = BuybackCalculator.defaultBuyFeeTotal.inputString
    @AppStorage("buybackCalculator.slippage") private var slippageText = BuybackCalculator.defaultSlippagePercent.inputString

    @StateObject private var lookup = MarketLookupViewModel()
    @StateObject private var apiKeys = APIKeySettingsViewModel()
    @StateObject private var scenarios = SavedScenarioStore()
    @State private var manualPriceEnabled = false
    @State private var advancedExpanded = false
    @State private var apiKeysExpanded = false
    @State private var settingsPresented = false
    @State private var scenarioMessage: LookupMessage?
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

    private var sellFeeTotal: Double? {
        BuybackCalculator.parseDecimal(sellFeeText)
    }

    private var buyFeeTotal: Double? {
        BuybackCalculator.parseDecimal(buyFeeText)
    }

    private var slippagePercent: Double? {
        BuybackCalculator.parseDecimal(slippageText)
    }

    private var calculation: BuybackCalculation? {
        guard let sellPrice,
              let gainPercent,
              let sharesToSell,
              let taxRatePercent,
              let targetExtraSharesPercent,
              let sellFeeTotal,
              let buyFeeTotal,
              let slippagePercent
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
            sellFeeTotal: sellFeeTotal,
            buyFeeTotal: buyFeeTotal,
            slippagePercent: slippagePercent,
            currencyCode: activeCurrencyCode
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    lookupPanel
                    if !apiKeys.hasUsableFinnhubAPIKey {
                        apiKeyPrompt
                    }
                    inputPanel

                    if let calculation {
                        resultSummary(calculation)
                        positionBreakdown(calculation)
                        sensitivitySection(calculation)
                        scenarioSection(calculation)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        settingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.glass)
                }

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
        .sheet(isPresented: $settingsPresented) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        apiKeyPanel
                        widgetStatus
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .background {
                    LiquidGlassBackground()
                        .ignoresSafeArea()
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            settingsPresented = false
                        }
                    }
                }
            }
            .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
        }
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
        .onOpenURL { url in
            handleDeepLink(url)
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                GlassBadge(title: "Price", value: sellPrice.map { $0.moneyString(currencyCode: activeCurrencyCode) } ?? "Missing")
                GlassBadge(title: "Tax", value: parsedText(taxRateText) + "%")
                GlassBadge(title: "Target", value: "+" + parsedText(targetExtraText) + "%")
                if (sellFeeTotal ?? 0) + (buyFeeTotal ?? 0) > 0 || (slippagePercent ?? 0) > 0 {
                    GlassBadge(title: "Costs", value: ((sellFeeTotal ?? 0) + (buyFeeTotal ?? 0)).moneyString(currencyCode: activeCurrencyCode))
                }
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

    private var apiKeyPrompt: some View {
        HStack(spacing: 12) {
            LiquidGlassIcon(systemImage: "key", tint: .orange, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Live prices are off")
                    .font(.headline)
                Text("Add a Finnhub key in Settings for autocomplete and live quote refreshes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                apiKeysExpanded = true
                settingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open API key settings")
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

                        decimalField(
                            "Extra shares target",
                            text: $targetExtraText,
                            suffix: "%",
                            icon: "arrow.up.forward.circle",
                            field: .targetExtra
                        )

                        decimalField(
                            "Slippage buffer",
                            text: $slippageText,
                            suffix: "%",
                            icon: "waveform.path.ecg",
                            field: .slippage
                        )

                        decimalField(
                            "Sell fees",
                            text: $sellFeeText,
                            suffix: activeCurrencyCode,
                            icon: "minus.circle",
                            field: .sellFee
                        )

                        decimalField(
                            "Buy fees",
                            text: $buyFeeText,
                            suffix: activeCurrencyCode,
                            icon: "plus.circle",
                            field: .buyFee
                        )
                    }

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
            MetricTile(title: "Buyback cash", value: calculation.cashAvailableForBuyback.moneyString(currencyCode: calculation.currencyCode), systemImage: "cart")
            MetricTile(title: "Tax estimate", value: calculation.taxAmount.moneyString(currencyCode: calculation.currencyCode), systemImage: "building.columns")
            MetricTile(title: "Target shares", value: calculation.targetShareCount.shareString, systemImage: "plus.forwardslash.minus")
            MetricTile(title: "Trading costs", value: (calculation.sellFeeTotal + calculation.buyFeeTotal).moneyString(currencyCode: calculation.currencyCode), systemImage: "receipt")
            MetricTile(title: "Slippage", value: calculation.slippagePercent.compactPercentString, systemImage: "waveform.path.ecg")
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

    private func scenarioSection(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SectionTitle("Scenarios", systemImage: "tray.full")
                Spacer(minLength: 8)

                Button {
                    saveScenario(calculation)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Save current scenario")
            }

            if let scenarioMessage {
                StatusRow(message: scenarioMessage)
            }

            if scenarios.scenarios.isEmpty {
                Text("No saved scenarios yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .liquidCardBackground(tint: LiquidPalette.blue.opacity(0.16))
            } else {
                VStack(spacing: 8) {
                    ForEach(scenarios.scenarios) { scenario in
                        SavedScenarioRow(scenario: scenario) {
                            loadScenario(scenario)
                        } onDelete: {
                            scenarios.delete(scenario)
                            scenarioMessage = .info("Scenario deleted.")
                        }
                    }
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

        guard let sellFeeTotal, sellFeeTotal >= 0 else {
            return "Sell fees must be 0 or higher."
        }

        guard let buyFeeTotal, buyFeeTotal >= 0 else {
            return "Buy fees must be 0 or higher."
        }

        guard let slippagePercent, slippagePercent >= 0 else {
            return "Slippage must be 0% or higher."
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
                sellFeeTotal: calculation.sellFeeTotal,
                buyFeeTotal: calculation.buyFeeTotal,
                slippagePercent: calculation.slippagePercent,
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

    private func saveScenario(_ calculation: BuybackCalculation) {
        let scenario = SavedBuybackScenario(
            id: UUID(),
            name: displayName,
            savedAt: .now,
            assetQuery: assetQuery,
            selectedAsset: lookup.selectedAsset,
            manualPriceEnabled: manualPriceEnabled,
            symbol: calculation.symbol,
            currencyCode: calculation.currencyCode,
            sellPrice: calculation.sellPrice,
            gainPercent: calculation.gainAtSellPercent,
            sharesToSell: calculation.sharesToSell,
            taxRatePercent: calculation.taxRatePercent,
            targetExtraSharesPercent: calculation.targetExtraSharesPercent,
            sellFeeTotal: calculation.sellFeeTotal,
            buyFeeTotal: calculation.buyFeeTotal,
            slippagePercent: calculation.slippagePercent
        )

        scenarios.save(scenario)
        scenarioMessage = .info("Scenario saved.")
    }

    private func loadScenario(_ scenario: SavedBuybackScenario) {
        sellPriceText = scenario.sellPrice.inputString
        gainPercentText = scenario.gainPercent.inputString
        sharesText = scenario.sharesToSell.inputString
        taxRateText = scenario.taxRatePercent.inputString
        targetExtraText = scenario.targetExtraSharesPercent.inputString
        sellFeeText = scenario.sellFeeTotal.inputString
        buyFeeText = scenario.buyFeeTotal.inputString
        slippageText = scenario.slippagePercent.inputString
        manualPriceEnabled = scenario.manualPriceEnabled
        focusedField = nil

        if let asset = scenario.selectedAsset {
            lookup.prepareSelection(asset)
            persist(asset)
            assetQuery = asset.symbol
            symbolText = asset.symbol

            if !scenario.manualPriceEnabled {
                refreshSelectedQuote()
            }
        } else {
            lookup.clearSelection()
            selectedAssetData = ""
            assetQuery = scenario.displaySymbol
            symbolText = scenario.displaySymbol
            lookup.scheduleSearch(query: scenario.displaySymbol)
        }

        scenarioMessage = .info("Scenario loaded.")
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "buybackcalculator" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func value(_ names: String...) -> String? {
            queryItems.first { item in
                names.contains { $0.caseInsensitiveCompare(item.name) == .orderedSame }
            }?.value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }

        let pathSymbol = url.pathComponents.dropFirst().first
        let candidate = value("symbol", "ticker") ?? pathSymbol ?? url.host

        if let symbol = candidate?.normalizedStockSymbol, !symbol.isEmpty {
            lookup.clearSelection()
            selectedAssetData = ""
            assetQuery = symbol
            symbolText = symbol
            lookup.scheduleSearch(query: symbol)
        }

        if let price = value("price", "sellPrice", "fallbackPrice") {
            sellPriceText = price
            manualPriceEnabled = true
        }

        if let gain = value("gain", "gainPercent", "gainAtSellPercent") {
            gainPercentText = gain
        }

        if let shares = value("shares", "sharesToSell") {
            sharesText = shares
        }

        scenarioMessage = .info("Loaded widget values.")
        focusedField = .gain
    }

    private func parsedText(_ text: String) -> String {
        BuybackCalculator.parseDecimal(text)?.inputString ?? text
    }
}

private enum CalculatorField: Hashable {
    case asset
    case price
    case gain
    case shares
    case taxRate
    case targetExtra
    case sellFee
    case buyFee
    case slippage
    case finnhubKey
    case openFIGIKey
}

private struct SensitivityRow: Identifiable {
    let id: String
    let label: String
    let sellPrice: Double
    let maximumBuybackPrice: Double
    let requiredDropPercent: Double
    let isBase: Bool
}

private struct SavedScenarioRow: View {
    let scenario: SavedBuybackScenario
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onLoad) {
                HStack(alignment: .center, spacing: 12) {
                    LiquidGlassIcon(systemImage: "bookmark.fill", tint: LiquidPalette.blue, size: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(scenario.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Delete saved scenario")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.blue.opacity(0.18))
    }

    private var subtitle: String {
        let savedDate = scenario.savedAt.formatted(date: .abbreviated, time: .shortened)
        guard let calculation = scenario.calculation else {
            return "\(scenario.displaySymbol) • saved \(savedDate)"
        }

        return "\(scenario.displaySymbol) • \(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode)) limit • saved \(savedDate)"
    }
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

#Preview("Lookup") {
    ContentView()
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
