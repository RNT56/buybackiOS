import SwiftUI
import WidgetKit

private enum ContentSheet: String, Identifiable {
    case settings
    case assetLookup
    case advancedCalculator
    case resultDetails

    var id: String {
        rawValue
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("buybackCalculator.assetQuery") private var assetQuery = BuybackCalculator.defaultSymbol
    @AppStorage("buybackCalculator.selectedAsset") private var selectedAssetData = ""
    @AppStorage("buybackCalculator.symbol") private var symbolText = BuybackCalculator.defaultSymbol
    @AppStorage("buybackCalculator.sellPrice") private var sellPriceText = BuybackCalculator.defaultSellPrice.inputString
    @AppStorage("buybackCalculator.gainPercent") private var gainPercentText = "463.10"
    @AppStorage("buybackCalculator.shares") private var sharesText = "1"
    @AppStorage("buybackCalculator.taxProfile") private var taxProfileRaw = BuybackCalculator.defaultTaxProfile.rawValue
    @AppStorage("buybackCalculator.taxRate") private var taxRateText = BuybackCalculator.fixedTaxRatePercent.inputString
    @AppStorage("buybackCalculator.taxCurrency") private var taxCurrencyText = BuybackCalculator.defaultCurrencyCode
    @AppStorage("buybackCalculator.fxRateToTaxCurrency") private var fxRateText = BuybackCalculator.defaultFXRateToTaxCurrency.inputString
    @AppStorage("buybackCalculator.targetExtra") private var targetExtraText = BuybackCalculator.fixedTargetExtraSharesPercent.inputString
    @AppStorage("buybackCalculator.sellFee") private var sellFeeText = BuybackCalculator.defaultSellFeeTotal.inputString
    @AppStorage("buybackCalculator.buyFee") private var buyFeeText = BuybackCalculator.defaultBuyFeeTotal.inputString
    @AppStorage("buybackCalculator.slippage") private var slippageText = BuybackCalculator.defaultSlippagePercent.inputString
    @AppStorage("buybackCalculator.taxLotsEnabled") private var taxLotsEnabled = false
    @AppStorage("buybackCalculator.lot1Shares") private var lot1SharesText = ""
    @AppStorage("buybackCalculator.lot1Basis") private var lot1BasisText = ""
    @AppStorage("buybackCalculator.lot2Shares") private var lot2SharesText = ""
    @AppStorage("buybackCalculator.lot2Basis") private var lot2BasisText = ""
    @AppStorage("buybackCalculator.lot3Shares") private var lot3SharesText = ""
    @AppStorage("buybackCalculator.lot3Basis") private var lot3BasisText = ""
    @AppStorage("buybackCalculator.alertPrice") private var alertPriceText = ""

    @StateObject private var lookup = MarketLookupViewModel()
    @StateObject private var apiKeys = APIKeySettingsViewModel()
    @StateObject private var scenarios = SavedScenarioStore()
    @StateObject private var alerts = PriceAlertStore()
    @State private var manualPriceEnabled = false
    @State private var apiKeysExpanded = false
    @State private var activeSheet: ContentSheet?
    @State private var scenarioMessage: LookupMessage?
    @State private var startupScheduled = false

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
        if taxProfile == .custom {
            return BuybackCalculator.parseDecimal(taxRateText)
        }

        return taxProfile.defaultTaxRatePercent
    }

    private var taxProfile: TaxProfile {
        TaxProfile(rawValue: taxProfileRaw) ?? BuybackCalculator.defaultTaxProfile
    }

    private var effectiveTaxRatePercent: Double? {
        taxRatePercent.map { taxProfile.resolvedTaxRatePercent(customRatePercent: $0) }
    }

    private var taxCurrencyCode: String {
        taxCurrencyText.normalizedCurrencyCode
    }

    private var fxRateToTaxCurrency: Double? {
        BuybackCalculator.parseDecimal(fxRateText)
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

    private var alertPrice: Double? {
        BuybackCalculator.parseDecimal(alertPriceText)
    }

    private var taxLots: [TaxLot] {
        [
            taxLot(sharesText: lot1SharesText, basisText: lot1BasisText),
            taxLot(sharesText: lot2SharesText, basisText: lot2BasisText),
            taxLot(sharesText: lot3SharesText, basisText: lot3BasisText)
        ].compactMap { $0 }
    }

    private var lotAverageCostBasis: Double? {
        TaxLot.weightedAverageCostBasis(taxLots)
    }

    private var lotSharesToSell: Double? {
        let shares = TaxLot.totalShares(taxLots)
        return shares > 0 ? shares : nil
    }

    private var calculation: BuybackCalculation? {
        guard let sellPrice,
              let taxRatePercent,
              let fxRateToTaxCurrency,
              let targetExtraSharesPercent,
              let sellFeeTotal,
              let buyFeeTotal,
              let slippagePercent
        else {
            return nil
        }

        if taxLotsEnabled,
           let lotSharesToSell,
           let lotAverageCostBasis {
            return BuybackCalculator.calculate(
                symbol: activeSymbol,
                sharesToSell: lotSharesToSell,
                averageCostBasis: lotAverageCostBasis,
                sellPrice: sellPrice,
                taxProfile: taxProfile,
                taxRatePercent: taxRatePercent,
                taxCurrencyCode: taxCurrencyCode,
                fxRateToTaxCurrency: fxRateToTaxCurrency,
                targetExtraSharesPercent: targetExtraSharesPercent,
                sellFeeTotal: sellFeeTotal,
                buyFeeTotal: buyFeeTotal,
                slippagePercent: slippagePercent,
                currencyCode: activeCurrencyCode
            )
        } else {
            guard let gainPercent,
                  let sharesToSell
            else {
                return nil
            }

            return BuybackCalculator.calculate(
                symbol: activeSymbol,
                sellPrice: sellPrice,
                gainAtSellPercent: gainPercent,
                sharesToSell: sharesToSell,
                taxProfile: taxProfile,
                taxRatePercent: taxRatePercent,
                taxCurrencyCode: taxCurrencyCode,
                fxRateToTaxCurrency: fxRateToTaxCurrency,
                targetExtraSharesPercent: targetExtraSharesPercent,
                sellFeeTotal: sellFeeTotal,
                buyFeeTotal: buyFeeTotal,
                slippagePercent: slippagePercent,
                currencyCode: activeCurrencyCode
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                contentLayout
                    .frame(maxWidth: usesSplitLayout ? 1180 : 760, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, floatingDockScrollPadding)
            }
            .background {
                LiquidGlassBackground()
                    .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) {
                launchActionDock(calculation: calculation)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Buy-Back")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        LiquidGlassActionIcon(icon: .keySettings, tint: LiquidPalette.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshSelectedQuote()
                    } label: {
                        LiquidGlassActionIcon(icon: .refresh)
                    }
                    .buttonStyle(.plain)
                    .disabled(lookup.selectedAsset == nil || lookup.isFetchingQuote)
                    .accessibilityLabel("Refresh price")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
        .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .onAppear {
            scheduleStartupIfNeeded()
        }
        .onChange(of: assetQuery) { _, newValue in
            if newValue.normalizedStockSymbol != lookup.selectedAsset?.symbol {
                lookup.clearSelection()
                selectedAssetData = ""
                symbolText = newValue.normalizedStockSymbol
            }
            lookup.scheduleSearch(query: newValue)
        }
        .onChange(of: taxProfileRaw) { _, newValue in
            guard let profile = TaxProfile(rawValue: newValue), profile != .custom else {
                return
            }
            taxRateText = profile.defaultTaxRatePercent.inputString
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private var usesSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ContentSheet) -> some View {
        switch sheet {
        case .settings:
            settingsSheet
        case .assetLookup:
            assetLookupSheet
        case .advancedCalculator:
            advancedCalculatorSheet
        case .resultDetails:
            resultDetailsSheet
        }
    }

    private var settingsSheet: some View {
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
                        activeSheet = nil
                    }
                }
            }
        }
        .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
    }

    private var assetLookupSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lookupPanel
                    if !apiKeys.hasUsableFinnhubAPIKey {
                        apiKeyPrompt
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background {
                LiquidGlassBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        activeSheet = nil
                    }
                }
            }
        }
        .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
    }

    private var resultDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let calculation {
                        resultDetails(calculation)
                    } else {
                        invalidState
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background {
                LiquidGlassBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        activeSheet = nil
                    }
                }
            }
        }
        .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
    }

    @ViewBuilder
    private var contentLayout: some View {
        if usesSplitLayout {
            HStack(alignment: .top, spacing: 18) {
                primaryInputColumn
                    .frame(maxWidth: 500, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 18) {
                    resultColumn
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let calculation {
                    resultSummary(calculation)
                    resultActionBar(calculation)
                } else {
                    invalidState
                }

                inputPanel
            }
        }
    }

    private var primaryInputColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            inputPanel
        }
    }

    private var floatingDockScrollPadding: CGFloat {
        104
    }

    @ViewBuilder
    private var resultColumn: some View {
        if let calculation {
            resultSummary(calculation)
            resultActionBar(calculation)
        } else {
            invalidState
        }
    }

    @ViewBuilder
    private func resultDetails(_ calculation: BuybackCalculation) -> some View {
            positionBreakdown(calculation)
            sensitivitySection(calculation)
            alertSection(calculation)
            scenarioSection(calculation)
    }

    private func launchActionDock(calculation: BuybackCalculation?) -> some View {
        HStack(spacing: 14) {
            iconActionButton(
                icon: .asset,
                tint: LiquidPalette.blue,
                accessibilityLabel: "Open asset lookup"
            ) {
                activeSheet = .assetLookup
            }

            iconActionButton(
                icon: .sliders,
                tint: LiquidPalette.accent,
                accessibilityLabel: "Open advanced calculator settings"
            ) {
                activeSheet = .advancedCalculator
            }

            iconActionButton(
                icon: .sensitivity,
                tint: .orange,
                accessibilityLabel: "Open calculation details",
                isDisabled: calculation == nil
            ) {
                activeSheet = .resultDetails
            }

            iconActionButton(
                icon: .keySettings,
                tint: LiquidPalette.blue,
                accessibilityLabel: "Open settings"
            ) {
                activeSheet = .settings
            }
        }
        .padding(.horizontal, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    activeSheet = .assetLookup
                } label: {
                    LiquidGlassIcon(icon: .appMark, tint: .teal, size: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open stock input")

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

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GlassBadge(title: "Price", value: sellPrice.map { $0.moneyString(currencyCode: activeCurrencyCode) } ?? "Missing")
                    GlassBadge(title: "Tax", value: (effectiveTaxRatePercent?.inputString ?? parsedText(taxRateText)) + "%")
                    GlassBadge(title: "Target", value: "+" + parsedText(targetExtraText) + "%")
                }

                if (sellFeeTotal ?? 0) + (buyFeeTotal ?? 0) > 0 || (slippagePercent ?? 0) > 0 {
                    GlassBadge(title: "Costs", value: ((sellFeeTotal ?? 0) + (buyFeeTotal ?? 0)).moneyString(currencyCode: activeCurrencyCode))
                }
            }
        }
    }

    private var lookupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Asset", icon: .asset)

            VStack(alignment: .leading, spacing: 8) {
                IconLabel("Name, ticker, ISIN, or WKN", icon: .lookupText, tint: .secondary, iconSize: 14)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("AAPL, Apple, US0378331005", text: $assetQuery)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 52)
                    .liquidFieldSurface()
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
            LiquidGlassIcon(icon: .key, tint: .orange, size: 38)

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
                activeSheet = .settings
            } label: {
                LiquidGlassActionIcon(icon: .keySettings, tint: LiquidPalette.blue, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open API key settings")
        }
        .liquidSurface()
    }

    private var apiKeyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                apiKeysExpanded.toggle()
            } label: {
                expansionHeader("API Keys", icon: apiKeys.hasUsableFinnhubAPIKey ? .apiKey : .key, isExpanded: apiKeysExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("API Keys")
            .accessibilityValue(apiKeysExpanded ? "Expanded" : "Collapsed")

            if apiKeysExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        IconLabel("Finnhub", icon: .live, tint: .secondary, iconSize: 14)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        SecureField("Required for live search and quotes", text: $apiKeys.finnhubAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(.horizontal, 13)
                            .frame(height: 50)
                            .liquidFieldSurface()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        IconLabel("OpenFIGI", icon: .apiKey, tint: .secondary, iconSize: 14)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        SecureField("Optional for higher identifier-map limits", text: $apiKeys.openFIGIAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(.horizontal, 13)
                            .frame(height: 50)
                            .liquidFieldSurface()
                    }

                    HStack(spacing: 10) {
                        Button {
                            apiKeys.save()
                            configureLookupClient()
                            lookup.scheduleSearch(query: assetQuery)
                        } label: {
                            LiquidGlassActionIcon(icon: .save, size: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save API keys")

                        Button(role: .destructive) {
                            apiKeys.clear()
                            configureLookupClient()
                            lookup.scheduleSearch(query: assetQuery)
                        } label: {
                            LiquidGlassActionIcon(icon: .clear, tint: .red, size: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear API keys")
                    }

                    StatusRow(message: apiKeyStatusMessage)
                }
            }
        }
        .liquidSurface()
    }

    private var inputPanel: some View {
        LaunchCalculatorPanel(
            sellPriceText: $sellPriceText,
            gainPercentText: $gainPercentText,
            manualPriceEnabled: $manualPriceEnabled,
            activeCurrencyCode: activeCurrencyCode,
            quote: lookup.quote,
            isFetchingQuote: lookup.isFetchingQuote,
            isPriceLocked: lookup.quote != nil && !manualPriceEnabled,
            isGainDisabled: taxLotsEnabled
        ) {
            activeSheet = .advancedCalculator
        }
        .liquidSurface()
    }

    private var advancedCalculatorSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    advancedPositionContent
                    advancedTaxContent
                    advancedCostsContent
                    advancedRefreshButton
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background {
                LiquidGlassBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        activeSheet = nil
                    }
                }
            }
        }
        .tint(Color(red: 0.02, green: 0.66, blue: 0.62))
    }

    private var advancedPositionContent: some View {
        advancedGroup("Position", icon: .shares) {
            VStack(alignment: .leading, spacing: 12) {
                decimalField("Shares", text: $sharesText, suffix: "sh", icon: .shares, field: .shares, isDisabled: taxLotsEnabled)
                decimalField("Extra shares target", text: $targetExtraText, suffix: "%", icon: .target, field: .targetExtra)
                toggleButton("Use tax lots", icon: .lots, isOn: $taxLotsEnabled)

                if taxLotsEnabled {
                    taxLotContent
                }
            }
        }
        .liquidSurface()
    }

    private var taxLotContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            taxLotRow(title: "Lot 1", shares: $lot1SharesText, basis: $lot1BasisText, sharesField: .lot1Shares, basisField: .lot1Basis)
            taxLotRow(title: "Lot 2", shares: $lot2SharesText, basis: $lot2BasisText, sharesField: .lot2Shares, basisField: .lot2Basis)
            taxLotRow(title: "Lot 3", shares: $lot3SharesText, basis: $lot3BasisText, sharesField: .lot3Shares, basisField: .lot3Basis)

            if let lotSharesToSell, let lotAverageCostBasis {
                StatusRow(message: .info("Selling \(lotSharesToSell.shareString) shares at weighted basis \(lotAverageCostBasis.moneyString(currencyCode: activeCurrencyCode))."))
            }
        }
    }

    private var advancedTaxContent: some View {
        advancedGroup("Tax", icon: .tax) {
            VStack(alignment: .leading, spacing: 8) {
                IconLabel("Tax profile", icon: .taxProfile, tint: .secondary, iconSize: 14)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Tax profile", selection: $taxProfileRaw) {
                    ForEach(TaxProfile.allCases) { profile in
                        Text(profile.label).tag(profile.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 12) {
                decimalField("Tax rate", text: $taxRateText, suffix: "%", icon: .taxRate, field: .taxRate, isDisabled: taxProfile != .custom)
                textField("Tax currency", text: $taxCurrencyText, suffix: "ccy", icon: .taxCurrency, field: .taxCurrency)
                decimalField("FX to tax currency", text: $fxRateText, suffix: "x", icon: .fx, field: .fxRate)
            }
        }
        .liquidSurface()
    }

    private var advancedCostsContent: some View {
        advancedGroup("Costs", icon: .costs) {
            VStack(alignment: .leading, spacing: 12) {
                decimalField("Slippage buffer", text: $slippageText, suffix: "%", icon: .slippage, field: .slippage)
                decimalField("Sell fees", text: $sellFeeText, suffix: activeCurrencyCode, icon: .sellFee, field: .sellFee)
                decimalField("Buy fees", text: $buyFeeText, suffix: activeCurrencyCode, icon: .buyFee, field: .buyFee)
            }
        }
        .liquidSurface()
    }

    private var advancedRefreshButton: some View {
        Button {
            refreshSelectedQuote()
        } label: {
            LiquidGlassActionIcon(icon: .refresh, size: 44)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(lookup.selectedAsset == nil || lookup.isFetchingQuote)
        .accessibilityLabel("Refresh selected price")
        .liquidSurface()
    }

    private func toggleButton(_ title: String, icon: BuybackIconKind, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                IconLabel(title, icon: icon, iconSize: 16)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                LiquidGlassIcon(
                    icon: isOn.wrappedValue ? .selected : .toggleOff,
                    tint: isOn.wrappedValue ? LiquidPalette.accent : .secondary,
                    size: 30
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    private func expansionHeader(_ title: String, icon: BuybackIconKind, isExpanded: Bool) -> some View {
        HStack(spacing: 10) {
            IconLabel(title, icon: icon, iconSize: 17)
                .font(.headline)

            Spacer(minLength: 8)

            BuybackIcon(.chevron, tint: .secondary)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    private func advancedGroup<Content: View>(
        _ title: String,
        icon: BuybackIconKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                BuybackIcon(icon, tint: LiquidPalette.accent)
                    .frame(width: 17, height: 17)

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            content()
        }
    }

    private func decimalField(
        _ title: String,
        text: Binding<String>,
        suffix: String,
        icon: BuybackIconKind,
        field: CalculatorField,
        keyboardType: UIKeyboardType = .decimalPad,
        isDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            IconLabel(title, icon: icon, tint: .secondary, iconSize: 14)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            HStack(spacing: 8) {
                TextField(title, text: text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            .liquidFieldSurface(isDisabled: isDisabled)
        }
    }

    private func textField(
        _ title: String,
        text: Binding<String>,
        suffix: String,
        icon: BuybackIconKind,
        field: CalculatorField,
        isDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            IconLabel(title, icon: icon, tint: .secondary, iconSize: 14)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            HStack(spacing: 8) {
                TextField(title, text: text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.weight(.semibold).monospaced())
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
            .liquidFieldSurface(isDisabled: isDisabled)
        }
    }

    private func taxLotRow(
        title: String,
        shares: Binding<String>,
        basis: Binding<String>,
        sharesField: CalculatorField,
        basisField: CalculatorField
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                decimalField("Shares", text: shares, suffix: "sh", icon: .shares, field: sharesField)
                decimalField("Basis", text: basis, suffix: activeCurrencyCode, icon: .basis, field: basisField)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.blue.opacity(0.14))
    }

    private func resultSummary(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                SectionTitle("Buy-back limit", icon: .limit)
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

    private func resultActionBar(_ calculation: BuybackCalculation) -> some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)

            iconActionButton(
                icon: .refresh,
                tint: LiquidPalette.blue,
                accessibilityLabel: "Refresh selected price",
                isDisabled: lookup.selectedAsset == nil || lookup.isFetchingQuote
            ) {
                refreshSelectedQuote()
            }

            iconActionButton(
                icon: .alertArmed,
                tint: .orange,
                accessibilityLabel: "Arm alert at buy-back limit"
            ) {
                alertPriceText = calculation.maximumBuybackPrice.inputString
                alerts.save(
                    symbol: calculation.symbol,
                    targetPrice: calculation.maximumBuybackPrice,
                    currencyCode: calculation.currencyCode
                )
                evaluateAlert(calculation)
            }

            iconActionButton(
                icon: .save,
                tint: LiquidPalette.accent,
                accessibilityLabel: "Save current scenario"
            ) {
                saveScenario(calculation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 4)
    }

    private func iconActionButton(
        icon: BuybackIconKind,
        tint: Color,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            LiquidGlassIcon(icon: icon, tint: tint, size: 54)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.42 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private func positionBreakdown(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metricGroup("Outcome", icon: .target) {
                metricRow("Required drop", value: calculation.requiredDropPercent.percentString, icon: .drop)
                subtleDivider
                metricRow("Gain at sale", value: calculation.gainAtSellPercent.percentString, icon: .percent)
                subtleDivider
                metricRow("Cost basis", value: calculation.averageCostBasis.moneyString(currencyCode: calculation.currencyCode), icon: .basis)
                subtleDivider
                metricRow("Target shares", value: calculation.targetShareCount.shareString, icon: .shares)
            }

            metricGroup("Cash flow", icon: .cash) {
                metricRow("After-tax cash", value: calculation.afterTaxCash.moneyString(currencyCode: calculation.currencyCode), icon: .cash)
                subtleDivider
                metricRow("Buyback cash", value: calculation.cashAvailableForBuyback.moneyString(currencyCode: calculation.currencyCode), icon: .buybackCash)
                subtleDivider
                metricRow("Trading costs", value: (calculation.sellFeeTotal + calculation.buyFeeTotal).moneyString(currencyCode: calculation.currencyCode), icon: .costs)
                subtleDivider
                metricRow("Slippage buffer", value: calculation.slippagePercent.compactPercentString, icon: .slippage)
            }

            metricGroup("Tax assumptions", icon: .tax) {
                metricRow("Tax estimate", value: calculation.taxAmount.moneyString(currencyCode: calculation.currencyCode), icon: .tax)
                subtleDivider
                metricRow("Tax currency", value: calculation.taxAmountInTaxCurrency.moneyString(currencyCode: calculation.taxCurrencyCode), icon: .taxCurrency)
                subtleDivider
                metricRow("Tax profile", value: calculation.taxProfile.label, icon: .taxProfile)
                if taxLotsEnabled {
                    subtleDivider
                    metricRow("Basis source", value: "Tax lots", icon: .lots)
                } else if calculation.fxRateToTaxCurrency != 1 || calculation.taxCurrencyCode != calculation.currencyCode {
                    subtleDivider
                    metricRow("FX rate", value: calculation.fxRateToTaxCurrency.inputString, icon: .fx)
                }
            }
        }
    }

    private func metricGroup<Rows: View>(
        _ title: String,
        icon: BuybackIconKind,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title, icon: icon)
            VStack(spacing: 0) {
                rows()
            }
        }
        .liquidSurface()
    }

    private func metricRow(_ title: String, value: String, icon: BuybackIconKind) -> some View {
        HStack(spacing: 11) {
            BuybackIcon(icon, tint: LiquidPalette.accent)
                .frame(width: 22, height: 22)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 9)
    }

    private var subtleDivider: some View {
        Divider()
            .opacity(0.42)
    }

    private func sensitivitySection(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Price sensitivity", icon: .sensitivity)

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
                    .background {
                        if row.isBase {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LiquidPalette.accent.opacity(0.10))
                        }
                    }
                }
            }
        }
        .liquidSurface()
    }

    private func scenarioSection(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SectionTitle("Scenarios", icon: .scenarios)
                Spacer(minLength: 8)

                Button {
                    saveScenario(calculation)
                } label: {
                    LiquidGlassActionIcon(icon: .save, size: 40)
                }
                .buttonStyle(.plain)
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
                            WidgetCenter.shared.reloadAllTimelines()
                            scenarioMessage = .info("Scenario deleted.")
                        }
                    }
                }
            }
        }
        .liquidSurface()
    }

    private func alertSection(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SectionTitle("Price alert", icon: .alert)
                Spacer(minLength: 8)

                Button {
                    alertPriceText = calculation.maximumBuybackPrice.inputString
                    alerts.save(
                        symbol: calculation.symbol,
                        targetPrice: calculation.maximumBuybackPrice,
                        currencyCode: calculation.currencyCode
                    )
                    evaluateAlert(calculation)
                } label: {
                    LiquidGlassActionIcon(icon: .alertArmed, tint: .orange, size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Arm alert at buy-back limit")
            }

            VStack(alignment: .leading, spacing: 12) {
                decimalField(
                    "Alert price",
                    text: $alertPriceText,
                    suffix: calculation.currencyCode,
                    icon: .alert,
                    field: .alertPrice
                )

                Button {
                    if let alertPrice {
                        alerts.save(
                            symbol: calculation.symbol,
                            targetPrice: alertPrice,
                            currencyCode: calculation.currencyCode
                        )
                        evaluateAlert(calculation)
                    }
                } label: {
                    LiquidGlassActionIcon(icon: .selected, size: 44)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .frame(height: 52)
                .accessibilityLabel("Arm alert")
            }

            if let alert = alerts.alert(for: calculation.symbol), alert.isEnabled {
                StatusRow(message: .info("Armed for \(alert.targetPrice.moneyString(currencyCode: alert.currencyCode)). Alerts are checked on quote refresh."))
            } else if let message = alerts.statusMessage {
                StatusRow(message: message)
            }

            if alerts.alert(for: calculation.symbol)?.isEnabled == true {
                Button(role: .destructive) {
                    alerts.disable(symbol: calculation.symbol)
                } label: {
                    LiquidGlassActionIcon(icon: .alertOff, tint: .red, size: 44)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Disable alert")
            }
        }
        .liquidSurface()
    }

    private var invalidState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                LiquidGlassIcon(icon: .warning, tint: .orange, size: 34)

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
            LiquidGlassIcon(icon: .widget, tint: LiquidPalette.blue, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Home Screen widget")
                    .font(.headline)
                Text("Save scenarios to fill the portfolio widget. Existing single-stock widgets can still be configured in widget settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                WidgetCenter.shared.reloadAllTimelines()
            } label: {
                LiquidGlassActionIcon(icon: .refresh, size: 38)
            }
            .buttonStyle(.plain)
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

        if taxLotsEnabled {
            guard lotSharesToSell != nil, lotAverageCostBasis != nil else {
                return "Enter at least one valid tax lot."
            }
        } else {
            guard let gainPercent else {
                return "Enter a numeric gain percentage."
            }

            guard gainPercent > -100 else {
                return "Gain must be greater than -100%."
            }

            guard let sharesToSell, sharesToSell > 0 else {
                return "Shares must be greater than 0."
            }
        }

        guard let effectiveTaxRatePercent,
              effectiveTaxRatePercent >= 0,
              effectiveTaxRatePercent <= 100
        else {
            return "Tax rate must be between 0% and 100%."
        }

        guard let fxRateToTaxCurrency, fxRateToTaxCurrency > 0 else {
            return "FX rate must be greater than 0."
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

        return "Enter valid calculator inputs."
    }

    private func sensitivityRows(for calculation: BuybackCalculation) -> [SensitivityRow] {
        [-0.05, -0.02, 0, 0.02, 0.05].compactMap { movement in
            let sellPrice = calculation.sellPrice * (1 + movement)

            guard let variant = BuybackCalculator.calculate(
                symbol: calculation.symbol,
                sharesToSell: calculation.sharesToSell,
                averageCostBasis: calculation.averageCostBasis,
                sellPrice: sellPrice,
                taxProfile: calculation.taxProfile,
                taxRatePercent: calculation.taxRatePercent,
                taxCurrencyCode: calculation.taxCurrencyCode,
                fxRateToTaxCurrency: calculation.fxRateToTaxCurrency,
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

        Task {
            if let quote = await lookup.fetchQuote(for: asset) {
                sellPriceText = quote.price.inputString
                manualPriceEnabled = false
                if let calculation {
                    evaluateAlert(calculation)
                }
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
                if let calculation {
                    evaluateAlert(calculation)
                }
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

    private func scheduleStartupIfNeeded() {
        guard !startupScheduled else { return }
        startupScheduled = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await apiKeys.loadAsync()
            configureLookupClient()
            apiKeysExpanded = !apiKeys.hasUsableFinnhubAPIKey
            restoreSelectionIfNeeded()
            lookup.scheduleSearch(query: assetQuery)
        }
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
            taxProfile: calculation.taxProfile,
            taxRatePercent: calculation.taxRatePercent,
            taxCurrencyCode: calculation.taxCurrencyCode,
            fxRateToTaxCurrency: calculation.fxRateToTaxCurrency,
            targetExtraSharesPercent: calculation.targetExtraSharesPercent,
            sellFeeTotal: calculation.sellFeeTotal,
            buyFeeTotal: calculation.buyFeeTotal,
            slippagePercent: calculation.slippagePercent,
            taxLotsEnabled: taxLotsEnabled,
            taxLots: taxLots
        )

        scenarios.save(scenario)
        WidgetCenter.shared.reloadAllTimelines()
        scenarioMessage = .info("Scenario saved.")
    }

    private func loadScenario(_ scenario: SavedBuybackScenario) {
        sellPriceText = scenario.sellPrice.inputString
        gainPercentText = scenario.gainPercent.inputString
        sharesText = scenario.sharesToSell.inputString
        taxProfileRaw = scenario.taxProfile.rawValue
        taxRateText = scenario.taxRatePercent.inputString
        taxCurrencyText = scenario.taxCurrencyCode
        fxRateText = scenario.fxRateToTaxCurrency.inputString
        targetExtraText = scenario.targetExtraSharesPercent.inputString
        sellFeeText = scenario.sellFeeTotal.inputString
        buyFeeText = scenario.buyFeeTotal.inputString
        slippageText = scenario.slippagePercent.inputString
        taxLotsEnabled = scenario.taxLotsEnabled
        applyTaxLots(scenario.taxLots)
        manualPriceEnabled = scenario.manualPriceEnabled

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

        if let taxProfile = value("taxProfile"),
           let profile = TaxProfile(rawValue: taxProfile) {
            taxProfileRaw = profile.rawValue
        }

        if let taxRate = value("taxRate", "taxRatePercent") {
            taxRateText = taxRate
        }

        if let taxCurrency = value("taxCurrency") {
            taxCurrencyText = taxCurrency
        }

        if let fxRate = value("fxRate", "fxRateToTaxCurrency") {
            fxRateText = fxRate
        }

        scenarioMessage = .info("Loaded widget values.")
    }

    private func taxLot(sharesText: String, basisText: String) -> TaxLot? {
        guard let shares = BuybackCalculator.parseDecimal(sharesText),
              let basis = BuybackCalculator.parseDecimal(basisText)
        else {
            return nil
        }

        let lot = TaxLot(shares: shares, averageCostBasis: basis)
        return lot.isValid ? lot : nil
    }

    private func applyTaxLots(_ lots: [TaxLot]) {
        let lotValues = Array(lots.prefix(3))
        lot1SharesText = lotValues.indices.contains(0) ? lotValues[0].shares.inputString : ""
        lot1BasisText = lotValues.indices.contains(0) ? lotValues[0].averageCostBasis.inputString : ""
        lot2SharesText = lotValues.indices.contains(1) ? lotValues[1].shares.inputString : ""
        lot2BasisText = lotValues.indices.contains(1) ? lotValues[1].averageCostBasis.inputString : ""
        lot3SharesText = lotValues.indices.contains(2) ? lotValues[2].shares.inputString : ""
        lot3BasisText = lotValues.indices.contains(2) ? lotValues[2].averageCostBasis.inputString : ""
    }

    private func evaluateAlert(_ calculation: BuybackCalculation) {
        guard let currentPrice = sellPrice else { return }
        alerts.evaluate(
            symbol: calculation.symbol,
            price: currentPrice,
            calculation: calculation
        )
    }

    private func parsedText(_ text: String) -> String {
        BuybackCalculator.parseDecimal(text)?.inputString ?? text
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct LaunchCalculatorPanel: View {
    @Binding var sellPriceText: String
    @Binding var gainPercentText: String
    @Binding var manualPriceEnabled: Bool

    let activeCurrencyCode: String
    let quote: MarketQuote?
    let isFetchingQuote: Bool
    let isPriceLocked: Bool
    let isGainDisabled: Bool
    let onOpenAdvanced: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SectionTitle("Calculator", icon: .calculator)

                Spacer(minLength: 8)

                Button(action: onOpenAdvanced) {
                    LiquidGlassActionIcon(icon: .sliders, size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open advanced calculator settings")
            }

            VStack(alignment: .leading, spacing: 12) {
                LaunchDecimalField(
                    title: "Current price",
                    text: $sellPriceText,
                    suffix: activeCurrencyCode,
                    icon: quote == nil || manualPriceEnabled ? .edit : .live,
                    isDisabled: isPriceLocked
                )

                LaunchDecimalField(
                    title: "Current gain",
                    text: $gainPercentText,
                    suffix: "%",
                    icon: .percent,
                    keyboardType: .numbersAndPunctuation,
                    isDisabled: isGainDisabled
                )
            }

            manualOverrideButton
            quoteStatus
        }
    }

    private var manualOverrideButton: some View {
        Button {
            manualPriceEnabled.toggle()
        } label: {
            HStack(spacing: 10) {
                IconLabel("Manual price override", icon: .edit, iconSize: 16)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                LiquidGlassIcon(
                    icon: manualPriceEnabled ? .selected : .toggleOff,
                    tint: manualPriceEnabled ? LiquidPalette.accent : .secondary,
                    size: 30
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manual price override")
        .accessibilityValue(manualPriceEnabled ? "On" : "Off")
    }

    @ViewBuilder
    private var quoteStatus: some View {
        if isFetchingQuote {
            HStack(spacing: 10) {
                ProgressView()
                Text("Fetching latest price")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidCapsuleSurface(tint: LiquidPalette.accent)
        } else if let quote {
            QuoteStatusRow(quote: quote, manualPriceEnabled: manualPriceEnabled)
        }
    }
}

private struct LaunchDecimalField: View {
    let title: String
    @Binding var text: String
    let suffix: String
    let icon: BuybackIconKind
    var keyboardType: UIKeyboardType = .decimalPad
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            IconLabel(title, icon: icon, tint: .secondary, iconSize: 14)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            HStack(spacing: 8) {
                TextField(title, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            .liquidFieldSurface(isDisabled: isDisabled)
        }
    }
}

private enum CalculatorField: Hashable {
    case asset
    case price
    case gain
    case shares
    case taxRate
    case taxCurrency
    case fxRate
    case targetExtra
    case sellFee
    case buyFee
    case slippage
    case lot1Shares
    case lot1Basis
    case lot2Shares
    case lot2Basis
    case lot3Shares
    case lot3Basis
    case alertPrice
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
                    LiquidGlassIcon(icon: .bookmark, tint: LiquidPalette.blue, size: 34)

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
                LiquidGlassActionIcon(icon: .clear, tint: .red, size: 38)
            }
            .buttonStyle(.plain)
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
            LiquidGlassIcon(icon: .market, tint: LiquidPalette.blue, size: 34)

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

            BuybackIcon(.chevron, tint: .secondary)
                .frame(width: 14, height: 14)
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
                icon: quote == nil ? .selected : .live,
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
            BuybackIcon(manualPriceEnabled ? .edit : .live, tint: manualPriceEnabled ? Color.orange : Color.accentColor)
                .frame(width: 18, height: 18)

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
            BuybackIcon(message.style == .warning ? .warning : .info, tint: message.style == .warning ? .orange : .secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

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
