import SwiftUI
import WidgetKit

private enum ContentSheet: String, Identifiable {
    case settings
    case assetLookup
    case advancedCalculator
    case resultDetails
    case freezeEditor

    var id: String {
        rawValue
    }
}

private enum DockAction: String, Hashable {
    case asset
    case advanced
    case details
    case settings
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case breakdown
    case scenarios

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakdown:
            return "Breakdown"
        case .scenarios:
            return "Scenarios"
        }
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
    @AppStorage("buybackCalculator.taxLots") private var taxLotsData = ""
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
    @State private var detailTab = DetailTab.breakdown
    @State private var scenarioMessage: LookupMessage?
    @State private var scenarioQuotes: [UUID: MarketQuote] = [:]
    @State private var scenarioMessages: [UUID: LookupMessage] = [:]
    @State private var scenarioRefreshingIDs: Set<UUID> = []
    @State private var isRefreshingScenarios = false
    @State private var editableTaxLots: [EditableTaxLot] = [EditableTaxLot()]
    @State private var taxLotsRestored = false
    @State private var startupScheduled = false
    @State private var shouldFocusAssetLookup = false
    @State private var selectedDockAction: DockAction = .asset
    @State private var freezeEditorScenario: SavedBuybackScenario?
    @State private var freezePriceText = ""
    @State private var freezeCurrencyCode = BuybackCalculator.defaultCurrencyCode
    @State private var freezeQuoteTimestamp: Date?
    @State private var topChromeBlurProgress = 0.0
    @Namespace private var dockSelectionNamespace
    @FocusState private var assetLookupFieldFocused: Bool

    private let targetExtraSliderUpperBound = 25.0

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

    private var normalizedTargetExtraSharesPercent: Double {
        guard let targetExtraSharesPercent, targetExtraSharesPercent.isFinite else {
            return BuybackCalculator.fixedTargetExtraSharesPercent
        }

        return max(0, targetExtraSharesPercent)
    }

    private var targetExtraDisplayText: String {
        guard let targetExtraSharesPercent, targetExtraSharesPercent.isFinite, targetExtraSharesPercent >= 0 else {
            return "Check"
        }

        return "+" + targetExtraSharesPercent.compactPercentString
    }

    private var targetExtraSliderValue: Binding<Double> {
        Binding(
            get: {
                min(normalizedTargetExtraSharesPercent, targetExtraSliderUpperBound)
            },
            set: { value in
                setTargetExtraSharesPercent(value)
            }
        )
    }

    private var targetExtraSharePreview: String {
        guard let targetExtraSharesPercent, targetExtraSharesPercent >= 0 else {
            return "Enter 0% or higher."
        }

        let baseShares = taxLotsEnabled ? lotSharesToSell : sharesToSell
        guard let baseShares, baseShares > 0 else {
            return "Set shares to preview the target count."
        }

        let targetShares = baseShares * (1 + targetExtraSharesPercent / 100)
        let extraShares = max(0, targetShares - baseShares)
        return "\(baseShares.shareString) sold -> \(targetShares.shareString) target shares (+\(extraShares.shareString))."
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
        editableTaxLots.compactMap(\.taxLot)
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
            ZStack(alignment: .top) {
                ScrollView {
                    contentLayout
                        .frame(maxWidth: usesSplitLayout ? 1180 : 760, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.top, topChromeScrollPadding)
                        .padding(.bottom, floatingDockScrollPadding)
                }
                .background {
                    LiquidGlassBackground()
                        .ignoresSafeArea()
                }
                .overlay(alignment: .top) {
                    topChromeBlurOverlay
                }
                .overlay(alignment: .bottom) {
                    launchActionDock(calculation: calculation)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    updateTopChromeBlurProgress(offset)
                }

                topNavigationChrome
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
        .tint(LiquidPalette.accent)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .onAppear {
            restoreTaxLotsIfNeeded()
            scheduleStartupIfNeeded()
        }
        .onChange(of: editableTaxLots) { _, _ in
            persistTaxLots()
        }
        .onChange(of: taxLotsEnabled) { _, isEnabled in
            if isEnabled {
                ensureEditableTaxLotRow()
            }
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
        case .freezeEditor:
            freezeEditorSheet
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
        .tint(LiquidPalette.accent)
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
        .tint(LiquidPalette.accent)
        .onAppear {
            if shouldFocusAssetLookup {
                focusAssetLookupField()
            }
        }
        .onDisappear {
            assetLookupFieldFocused = false
            shouldFocusAssetLookup = false
        }
    }

    private var resultDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let calculation {
                        Picker("Details", selection: $detailTab) {
                            ForEach(DetailTab.allCases) { tab in
                                Text(tab.label).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch detailTab {
                        case .breakdown:
                            resultDetails(calculation)
                        case .scenarios:
                            scenarioComparisonSection(calculation)
                        }
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
        .tint(LiquidPalette.accent)
    }

    private var freezeEditorSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(freezeEditorScenario?.isFrozen == true ? "Edit freeze" : "Freeze sell price", icon: .bookmark)

                        if let scenario = freezeEditorScenario {
                            StatusRow(message: .info("Freeze \(scenario.displaySymbol) at the actual sell price. The rebuy limit will stay based on this price while live quotes track the buy-back opportunity."))
                        }

                        decimalField(
                            "Frozen sell price",
                            text: $freezePriceText,
                            suffix: freezeCurrencyCode,
                            icon: .price
                        )

                        Button {
                            confirmFreezeEditor()
                        } label: {
                            LiquidGlassActionIcon(icon: .selected, size: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .frame(height: 52)
                        .accessibilityLabel("Save frozen sell price")
                    }
                    .liquidSurface()
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background {
                LiquidGlassBackground()
                    .ignoresSafeArea()
            }
            .navigationTitle("Freeze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        activeSheet = nil
                    }
                }
            }
        }
        .tint(LiquidPalette.accent)
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
        72
    }

    private var topChromeScrollPadding: CGFloat {
        76
    }

    private var topNavigationChrome: some View {
        HStack(alignment: .center) {
            Button {
                selectDockAction(.settings)
                activeSheet = .settings
            } label: {
                LiquidToolbarIcon(icon: .keySettings, controlSize: 46)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Spacer(minLength: 12)

            Text("Buy-Back")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            Button {
                refreshSelectedQuote()
            } label: {
                LiquidToolbarIcon(icon: .refresh, controlSize: 46)
            }
            .buttonStyle(.plain)
            .disabled(lookup.selectedAsset == nil || lookup.isFetchingQuote)
            .accessibilityLabel("Refresh price")
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .zIndex(10)
    }

    private var topChromeBlurOverlay: some View {
        TopChromeBlurBackground(progress: topChromeBlurProgress)
            .frame(height: 105)
            .offset(y: -10)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(9)
    }

    private func updateTopChromeBlurProgress(_ offset: CGFloat) {
        let progress = min(1, Double(max(0, offset) / 26))

        guard abs(progress - topChromeBlurProgress) > 0.015 else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            topChromeBlurProgress = progress
        }
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
        calculationTrace(calculation)
        sensitivitySection(calculation)
        alertSection(calculation)
    }

    private func launchActionDock(calculation: BuybackCalculation?) -> some View {
        HStack(spacing: 6) {
            dockIconButton(
                action: .asset,
                icon: .asset,
                role: .accent,
                accessibilityLabel: "Open asset lookup"
            ) {
                openAssetLookup()
            }

            dockIconButton(
                action: .advanced,
                icon: .sliders,
                role: .accent,
                accessibilityLabel: "Open advanced calculator settings"
            ) {
                activeSheet = .advancedCalculator
            }

            dockIconButton(
                action: .details,
                icon: .sensitivity,
                role: .muted,
                accessibilityLabel: "Open calculation details",
                isDisabled: calculation == nil
            ) {
                activeSheet = .resultDetails
            }

            dockIconButton(
                action: .settings,
                icon: .keySettings,
                role: .accent,
                accessibilityLabel: "Open settings"
            ) {
                activeSheet = .settings
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(LiquidPalette.glassTint.opacity(0.040))
                }
                .glassEffect(.regular.tint(LiquidPalette.glassTint.opacity(0.070)).interactive(), in: Capsule())
        }
        .shadow(color: .black.opacity(0.055), radius: 15, y: 7)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selectedDockAction)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                LiquidGlassActionIcon(icon: .appMark, tint: LiquidPalette.accent, size: 46)

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
            .contentShape(Rectangle())
            .onTapGesture {
                openAssetLookup()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open stock input")
            .accessibilityHint("Search by company name, ticker, ISIN, or WKN.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                openAssetLookup()
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
                    .focused($assetLookupFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        selectFirstSuggestedAsset()
                    }
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
                .liquidCapsuleSurface(tint: LiquidPalette.accent)
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
            LiquidGlassIcon(icon: .key, tint: LiquidPalette.muted, size: 38)

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
                selectDockAction(.settings)
                activeSheet = .settings
            } label: {
                LiquidGlassActionIcon(icon: .keySettings, tint: LiquidPalette.accent, size: 38)
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

                    if let validationMessage = apiKeys.validationMessage {
                        StatusRow(message: .warning(validationMessage))
                    }

                    HStack(spacing: 10) {
                        Button {
                            apiKeys.save()
                            configureLookupClient()
                            lookup.scheduleSearch(query: assetQuery)
                            WidgetCenter.shared.reloadAllTimelines()
                        } label: {
                            LiquidGlassActionIcon(icon: .save, size: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .disabled(!apiKeys.canSave)
                        .accessibilityLabel("Save API keys")

                        Button(role: .destructive) {
                            apiKeys.clear()
                            configureLookupClient()
                            lookup.scheduleSearch(query: assetQuery)
                            WidgetCenter.shared.reloadAllTimelines()
                        } label: {
                            LiquidGlassActionIcon(icon: .clear, tint: LiquidPalette.danger, size: 44)
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
            selectDockAction(.advanced)
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
        .tint(LiquidPalette.accent)
    }

    private var advancedPositionContent: some View {
        advancedGroup("Position", icon: .shares) {
            VStack(alignment: .leading, spacing: 12) {
                decimalField("Shares", text: $sharesText, suffix: "sh", icon: .shares, isDisabled: taxLotsEnabled)
                targetExtraSharesSelector
                toggleButton("Use tax lots", icon: .lots, isOn: $taxLotsEnabled)

                if taxLotsEnabled {
                    taxLotContent
                }
            }
        }
        .liquidSurface()
    }

    private var targetExtraSharesSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                IconLabel("Extra shares target", icon: .target, tint: .secondary, iconSize: 14)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Spacer(minLength: 8)

                Text(targetExtraDisplayText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .liquidCapsuleSurface(tint: LiquidPalette.accent.opacity(0.55))
            }

            Slider(
                value: targetExtraSliderValue,
                in: 0...targetExtraSliderUpperBound,
                step: 0.1
            ) {
                Text("Extra shares target")
            } minimumValueLabel: {
                Text("0%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(Int(targetExtraSliderUpperBound))%+")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .tint(LiquidPalette.accent)

            HStack(spacing: 9) {
                targetExtraStepButton(symbol: "minus", accessibilityLabel: "Decrease extra shares target") {
                    adjustTargetExtraSharesPercent(by: -0.5)
                }
                .disabled(normalizedTargetExtraSharesPercent <= 0)

                HStack(spacing: 8) {
                    TextField("Extra shares target", text: $targetExtraText)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .lineLimit(1)

                    Text("%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .frame(height: 48)
                .liquidFieldSurface(isDisabled: false)

                targetExtraStepButton(symbol: "plus", accessibilityLabel: "Increase extra shares target") {
                    adjustTargetExtraSharesPercent(by: 0.5)
                }
            }

            HStack(spacing: 8) {
                BuybackIcon(.shares, tint: LiquidPalette.accent)
                    .frame(width: 15, height: 15)

                Text(targetExtraSharePreview)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidCapsuleSurface(tint: LiquidPalette.accent.opacity(0.55))
        }
        .accessibilityElement(children: .contain)
    }

    private var taxLotContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($editableTaxLots) { $lot in
                taxLotRow(lot: $lot, index: taxLotIndex(for: lot.id))
            }

            Button {
                addTaxLotRow()
            } label: {
                HStack(spacing: 10) {
                    IconLabel("Add lot", icon: .lots, iconSize: 16)
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    LiquidGlassActionIcon(icon: .selected, size: 34)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add tax lot")

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
                decimalField("Tax rate", text: $taxRateText, suffix: "%", icon: .taxRate, isDisabled: taxProfile != .custom)
                textField("Tax currency", text: $taxCurrencyText, suffix: "ccy", icon: .taxCurrency)
                decimalField("FX to tax currency", text: $fxRateText, suffix: "x", icon: .fx)
            }

            VStack(alignment: .leading, spacing: 6) {
                IconLabel(taxProfile.assumptionSummary, icon: .info, tint: .secondary, iconSize: 14)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(taxProfile.assumptionDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .liquidCardBackground(tint: LiquidPalette.muted.opacity(0.16))
        }
        .liquidSurface()
    }

    private var advancedCostsContent: some View {
        advancedGroup("Costs", icon: .costs) {
            VStack(alignment: .leading, spacing: 12) {
                decimalField("Slippage buffer", text: $slippageText, suffix: "%", icon: .slippage)
                decimalField("Sell fees", text: $sellFeeText, suffix: activeCurrencyCode, icon: .sellFee)
                decimalField("Buy fees", text: $buyFeeText, suffix: activeCurrencyCode, icon: .buyFee)
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

    private func targetExtraStepButton(
        symbol: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            LiquidIconButton(
                systemName: symbol,
                role: .accent,
                size: 40,
                prominence: .inline
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
        lot: Binding<EditableTaxLot>,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Lot \(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer(minLength: 8)

                if editableTaxLots.count > 1 {
                    Button(role: .destructive) {
                        removeTaxLotRow(id: lot.wrappedValue.id)
                    } label: {
                        LiquidGlassActionIcon(icon: .clear, tint: LiquidPalette.danger, size: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tax lot \(index + 1)")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                decimalField("Shares", text: lot.sharesText, suffix: "sh", icon: .shares)
                decimalField("Basis", text: lot.basisText, suffix: activeCurrencyCode, icon: .basis)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.14))
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
                role: .accent,
                accessibilityLabel: "Refresh selected price",
                isDisabled: lookup.selectedAsset == nil || lookup.isFetchingQuote
            ) {
                refreshSelectedQuote()
            }

            iconActionButton(
                icon: .alertArmed,
                role: .muted,
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
                icon: .bookmark,
                role: .muted,
                accessibilityLabel: "Freeze current sell price"
            ) {
                freezeCurrentScenario(calculation)
            }

            iconActionButton(
                icon: .save,
                role: .accent,
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
        role: LiquidIconButtonRole,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isDisabled else { return }
            action()
        } label: {
            LiquidIconButton(
                icon: icon,
                role: role,
                prominence: .action,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isDisabled ? "Unavailable" : "")
    }

    private func dockIconButton(
        action dockAction: DockAction,
        icon: BuybackIconKind,
        role: LiquidIconButtonRole,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = selectedDockAction == dockAction

        return Button {
            guard !isDisabled else { return }
            selectDockAction(dockAction)
            action()
        } label: {
            ZStack {
                if isSelected {
                    dockSelectionLens(role: role)
                }

                LiquidIconButton(
                    icon: icon,
                    role: role,
                    size: 44,
                    prominence: .dock,
                    isSelected: isSelected,
                    isDisabled: isDisabled,
                    showsGlyph: false
                )

                dockGlyph(icon: icon, isSelected: isSelected, isDisabled: isDisabled)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isDisabled ? "Unavailable" : (isSelected ? "Selected" : ""))
    }

    private func dockGlyph(icon: BuybackIconKind, isSelected: Bool, isDisabled: Bool) -> some View {
        let opacity = isDisabled ? 0.76 : 0.98
        let glyphSize: CGFloat = isSelected ? 21 : 20
        let symbolName = dockSymbolName(for: icon)

        return Image(systemName: symbolName)
            .font(.system(size: glyphSize, weight: isSelected ? .medium : .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.white.opacity(opacity))
            .frame(width: 24, height: 24)
            .shadow(color: Color.black.opacity(isDisabled ? 0.20 : 0.30), radius: isSelected ? 1.5 : 1.15, y: 0.7)
            .compositingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func dockSymbolName(for icon: BuybackIconKind) -> String {
        switch icon {
        case .asset:
            return "magnifyingglass"
        case .sliders:
            return "slider.horizontal.3"
        case .sensitivity:
            return "chart.line.uptrend.xyaxis"
        case .keySettings:
            return "key"
        default:
            return "circle"
        }
    }

    private func dockSelectionLens(role: LiquidIconButtonRole) -> some View {
        let shape = Circle()
        let tint = role.tint

        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(tint.opacity(0.070))
            }
            .glassEffect(.regular.tint(tint.opacity(0.115)).interactive(), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.46), lineWidth: 1.1)
            }
            .frame(width: 51, height: 51)
            .shadow(color: .black.opacity(0.115), radius: 13, y: 5)
            .matchedGeometryEffect(id: "dockSelectionLens", in: dockSelectionNamespace)
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
                subtleDivider
                metricRow("Assumption", value: calculation.taxProfile.assumptionSummary, icon: .info)
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

    private func calculationTrace(_ calculation: BuybackCalculation) -> some View {
        metricGroup("Calculation trace", icon: .calculator) {
            traceRow(
                "Gross sale",
                value: calculation.grossProceeds.moneyString(currencyCode: calculation.currencyCode),
                detail: "\(calculation.sharesToSell.shareString) shares x \(calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode))",
                icon: .price
            )
            subtleDivider
            traceRow(
                "Net sale proceeds",
                value: calculation.netSaleProceeds.moneyString(currencyCode: calculation.currencyCode),
                detail: "Gross sale minus \(calculation.sellFeeTotal.moneyString(currencyCode: calculation.currencyCode)) sell fees",
                icon: .cash
            )
            subtleDivider
            traceRow(
                "Taxable gain",
                value: calculation.taxableGainTotal.moneyString(currencyCode: calculation.currencyCode),
                detail: "Net sale proceeds minus \(calculation.costBasisTotal.moneyString(currencyCode: calculation.currencyCode)) cost basis",
                icon: .tax
            )
            subtleDivider
            traceRow(
                "After-tax cash",
                value: calculation.afterTaxCash.moneyString(currencyCode: calculation.currencyCode),
                detail: "Net sale proceeds minus \(calculation.taxAmount.moneyString(currencyCode: calculation.currencyCode)) tax estimate",
                icon: .cash
            )
            subtleDivider
            traceRow(
                "Buyback cash",
                value: calculation.cashAvailableForBuyback.moneyString(currencyCode: calculation.currencyCode),
                detail: "After-tax cash minus \(calculation.buyFeeTotal.moneyString(currencyCode: calculation.currencyCode)) buy fees",
                icon: .buybackCash
            )
            subtleDivider
            traceRow(
                "Maximum buy-back price",
                value: calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode),
                detail: "\(calculation.targetShareCount.shareString) target shares with \(calculation.slippagePercent.compactPercentString) slippage buffer",
                icon: .limit
            )
        }
    }

    private func traceRow(_ title: String, value: String, detail: String, icon: BuybackIconKind) -> some View {
        HStack(alignment: .top, spacing: 11) {
            BuybackIcon(icon, tint: LiquidPalette.accent)
                .frame(width: 22, height: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
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

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
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
                                .foregroundStyle(row.isBase ? LiquidPalette.accent : Color.secondary)
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
                            RoundedRectangle(cornerRadius: LiquidMetrics.compactCardRadius, style: .continuous)
                                .fill(LiquidPalette.accent.opacity(0.10))
                        }
                    }
                }
            }
        }
        .liquidSurface()
    }

    private func scenarioComparisonSection(_ calculation: BuybackCalculation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SectionTitle("Scenarios", icon: .scenarios)
                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Button {
                        saveScenario(calculation)
                    } label: {
                        LiquidGlassActionIcon(icon: .save, size: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save current scenario")

                    Button {
                        refreshScenarioQuotes()
                    } label: {
                        LiquidGlassActionIcon(icon: .refresh, tint: LiquidPalette.accent, size: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(scenarios.scenarios.isEmpty || isRefreshingScenarios)
                    .accessibilityLabel("Refresh all saved scenario prices")
                }
            }

            if let scenarioMessage {
                StatusRow(message: scenarioMessage)
            }

            StatusRow(message: .info("Watching scenarios model the live quote as the sell price. Frozen scenarios keep the sell price fixed and compare the buy-back limit against refreshed live prices."))

            if scenarios.scenarios.isEmpty {
                Text("No saved scenarios yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.16))
            } else {
                VStack(spacing: 8) {
                    ForEach(scenarios.scenarios) { scenario in
                        ScenarioComparisonRow(
                            scenario: scenario,
                            quote: scenarioQuotes[scenario.id],
                            calculation: scenario.calculation(using: scenarioQuotes[scenario.id]),
                            alert: alerts.alert(for: scenario.displaySymbol),
                            message: scenarioMessages[scenario.id],
                            isRefreshing: scenarioRefreshingIDs.contains(scenario.id)
                        ) {
                            loadScenario(scenario)
                        } onFreeze: {
                            openFreezeEditor(scenario)
                        } onEditFreeze: {
                            openFreezeEditor(scenario)
                        } onUnfreeze: {
                            unfreezeScenario(scenario)
                        } onDelete: {
                            scenarios.delete(scenario)
                            scenarioQuotes.removeValue(forKey: scenario.id)
                            scenarioMessages.removeValue(forKey: scenario.id)
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
                    LiquidGlassActionIcon(icon: .alertArmed, tint: LiquidPalette.muted, size: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Arm alert at buy-back limit")
            }

            VStack(alignment: .leading, spacing: 12) {
                decimalField(
                    "Alert price",
                    text: $alertPriceText,
                    suffix: calculation.currencyCode,
                    icon: .alert
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
                StatusRow(message: .info("Armed for \(alert.targetPrice.moneyString(currencyCode: alert.currencyCode)). Checked when you refresh prices in the app or scenario dashboard."))
            } else if let message = alerts.statusMessage {
                StatusRow(message: message)
            } else {
                StatusRow(message: .info("Local alerts are checked when app prices refresh. They do not monitor prices continuously in the background."))
            }

            if alerts.alert(for: calculation.symbol)?.isEnabled == true {
                Button(role: .destructive) {
                    alerts.disable(symbol: calculation.symbol)
                } label: {
                    LiquidGlassActionIcon(icon: .alertOff, tint: LiquidPalette.danger, size: 44)
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
                LiquidGlassIcon(icon: .warning, tint: LiquidPalette.muted, size: 34)

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
            LiquidGlassIcon(icon: .widget, tint: LiquidPalette.accent, size: 38)

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

    private func setTargetExtraSharesPercent(_ value: Double) {
        let roundedValue = max(0, (value * 10).rounded() / 10)
        targetExtraText = roundedValue.inputString
    }

    private func adjustTargetExtraSharesPercent(by delta: Double) {
        setTargetExtraSharesPercent(normalizedTargetExtraSharesPercent + delta)
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

    private func openAssetLookup() {
        selectDockAction(.asset)
        shouldFocusAssetLookup = true
        activeSheet = .assetLookup
        focusAssetLookupField()
    }

    private func selectDockAction(_ action: DockAction) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            selectedDockAction = action
        }
    }

    private func focusAssetLookupField() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard activeSheet == .assetLookup else { return }
            assetLookupFieldFocused = true
        }
    }

    private func selectFirstSuggestedAsset() {
        guard let asset = lookup.suggestions.first else { return }
        select(asset)
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
        let scenario = makeScenario(calculation)
        scenarios.save(scenario)
        WidgetCenter.shared.reloadAllTimelines()
        scenarioMessage = .info("Scenario saved.")
    }

    private func freezeCurrentScenario(_ calculation: BuybackCalculation) {
        let scenario = makeScenario(
            calculation,
            trackingState: .frozen,
            frozenSellPrice: calculation.sellPrice,
            frozenCurrencyCode: calculation.currencyCode,
            frozenAt: .now,
            frozenQuoteTimestamp: lookup.quote?.timestamp
        )
        scenarios.save(scenario)
        WidgetCenter.shared.reloadAllTimelines()
        scenarioMessage = .info("\(calculation.displaySymbol) frozen at \(calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode)).")
    }

    private func makeScenario(
        _ calculation: BuybackCalculation,
        trackingState: ScenarioTrackingState = .watching,
        frozenSellPrice: Double? = nil,
        frozenCurrencyCode: String? = nil,
        frozenAt: Date? = nil,
        frozenQuoteTimestamp: Date? = nil
    ) -> SavedBuybackScenario {
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
            averageCostBasis: calculation.averageCostBasis,
            taxProfile: calculation.taxProfile,
            taxRatePercent: calculation.taxRatePercent,
            taxCurrencyCode: calculation.taxCurrencyCode,
            fxRateToTaxCurrency: calculation.fxRateToTaxCurrency,
            targetExtraSharesPercent: calculation.targetExtraSharesPercent,
            sellFeeTotal: calculation.sellFeeTotal,
            buyFeeTotal: calculation.buyFeeTotal,
            slippagePercent: calculation.slippagePercent,
            taxLotsEnabled: taxLotsEnabled,
            taxLots: taxLots,
            trackingState: trackingState,
            frozenSellPrice: frozenSellPrice,
            frozenCurrencyCode: frozenCurrencyCode,
            frozenAt: frozenAt,
            frozenQuoteTimestamp: frozenQuoteTimestamp
        )
        return scenario
    }

    private func loadScenario(_ scenario: SavedBuybackScenario) {
        sellPriceText = (scenario.activeSellPrice(using: scenarioQuotes[scenario.id]) ?? scenario.sellPrice).inputString
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
        manualPriceEnabled = scenario.manualPriceEnabled || scenario.isFrozen

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

    private func refreshScenarioQuotes() {
        guard !isRefreshingScenarios else { return }
        let savedScenarios = scenarios.scenarios
        guard !savedScenarios.isEmpty else { return }

        isRefreshingScenarios = true
        scenarioRefreshingIDs = Set(savedScenarios.map(\.id))
        scenarioMessage = .info("Refreshing saved scenario prices.")

        Task { @MainActor in
            guard let client = MarketDataClientFactory.make(
                finnhubAPIKey: apiKeys.effectiveFinnhubAPIKey,
                openFIGIAPIKey: apiKeys.effectiveOpenFIGIAPIKey,
                includeSavedKeys: true
            ) else {
                savedScenarios.forEach { scenario in
                    scenarioMessages[scenario.id] = .warning("Using saved price. Add a Finnhub key for live scenario refresh.")
                }
                scenarioRefreshingIDs.removeAll()
                isRefreshingScenarios = false
                scenarioMessage = .warning("Live scenario refresh needs a Finnhub API key.")
                return
            }

            for scenario in savedScenarios {
                await refreshScenarioQuote(scenario, client: client)
            }

            scenarioRefreshingIDs.removeAll()
            isRefreshingScenarios = false
            scenarioMessage = .info("Scenario prices refreshed.")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func refreshScenarioQuote(_ scenario: SavedBuybackScenario, client: CompositeMarketDataClient) async {
        scenarioMessages[scenario.id] = nil

        do {
            let quote = try await client.quote(for: scenario.portfolioAsset)
            scenarioQuotes[scenario.id] = quote
            scenarioMessages[scenario.id] = quote.isStale
                ? .warning(quote.statusMessage ?? "Live price is stale; verify before trading.")
                : .info("Live price updated.")

            if let calculation = scenario.calculation(using: quote) {
                alerts.evaluate(symbol: calculation.symbol, price: quote.price, calculation: calculation)
            }
        } catch {
            scenarioQuotes.removeValue(forKey: scenario.id)
            scenarioMessages[scenario.id] = .warning("Using saved price. \(marketDataMessage(for: error))")
        }

        scenarioRefreshingIDs.remove(scenario.id)
    }

    private func openFreezeEditor(_ scenario: SavedBuybackScenario) {
        let quote = scenarioQuotes[scenario.id]
        let seedPrice = quote?.price ?? scenario.frozenSellPrice ?? scenario.sellPrice
        freezeEditorScenario = scenario
        freezePriceText = seedPrice.inputString
        freezeCurrencyCode = (quote?.currencyCode ?? scenario.frozenCurrencyCode ?? scenario.currencyCode).normalizedCurrencyCode
        freezeQuoteTimestamp = quote?.timestamp
        activeSheet = .freezeEditor
    }

    private func confirmFreezeEditor() {
        guard let scenario = freezeEditorScenario else {
            scenarioMessage = .warning("Choose a saved scenario to freeze.")
            return
        }
        guard let price = BuybackCalculator.parseDecimal(freezePriceText),
              price.isFinite,
              price > 0
        else {
            scenarioMessage = .warning("Enter a valid frozen sell price.")
            return
        }

        guard SavedScenarioStorage.freezeScenario(
            id: scenario.id,
            sellPrice: price,
            currencyCode: freezeCurrencyCode,
            quoteTimestamp: freezeQuoteTimestamp
        ) else {
            scenarioMessage = .warning("Could not freeze \(scenario.displaySymbol).")
            return
        }

        scenarios.reload()
        WidgetCenter.shared.reloadAllTimelines()
        scenarioMessage = .info("\(scenario.displaySymbol) frozen at \(price.moneyString(currencyCode: freezeCurrencyCode)).")
        activeSheet = nil
    }

    private func unfreezeScenario(_ scenario: SavedBuybackScenario) {
        guard SavedScenarioStorage.unfreezeScenario(id: scenario.id) else {
            scenarioMessage = .warning("Could not unfreeze \(scenario.displaySymbol).")
            return
        }

        scenarios.reload()
        WidgetCenter.shared.reloadAllTimelines()
        scenarioMessage = .info("\(scenario.displaySymbol) is watching live prices again.")
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

    private func marketDataMessage(for error: Error) -> String {
        if let marketDataError = error as? MarketDataError {
            return marketDataError.localizedDescription
        }
        return "Market-data request failed."
    }

    private func applyTaxLots(_ lots: [TaxLot]) {
        editableTaxLots = lots.isEmpty ? [EditableTaxLot()] : lots.map(EditableTaxLot.init(lot:))
        persistTaxLots()
    }

    private func restoreTaxLotsIfNeeded() {
        guard !taxLotsRestored else { return }
        taxLotsRestored = true

        let savedLots = TaxLotDraftStorage.decode(taxLotsData)
        if !savedLots.isEmpty {
            editableTaxLots = savedLots.map(EditableTaxLot.init(lot:))
            return
        }

        let legacyLots = TaxLotDraftStorage.legacyLots(
            lot1Shares: lot1SharesText,
            lot1Basis: lot1BasisText,
            lot2Shares: lot2SharesText,
            lot2Basis: lot2BasisText,
            lot3Shares: lot3SharesText,
            lot3Basis: lot3BasisText
        )

        editableTaxLots = legacyLots.isEmpty ? [EditableTaxLot()] : legacyLots.map(EditableTaxLot.init(lot:))
        if !legacyLots.isEmpty {
            taxLotsData = TaxLotDraftStorage.encode(legacyLots)
        }
    }

    private func persistTaxLots() {
        guard taxLotsRestored else { return }
        taxLotsData = TaxLotDraftStorage.encode(taxLots)
    }

    private func ensureEditableTaxLotRow() {
        if editableTaxLots.isEmpty {
            editableTaxLots = [EditableTaxLot()]
        }
    }

    private func addTaxLotRow() {
        editableTaxLots.append(EditableTaxLot())
    }

    private func removeTaxLotRow(id: UUID) {
        editableTaxLots.removeAll { $0.id == id }
        ensureEditableTaxLotRow()
    }

    private func taxLotIndex(for id: UUID) -> Int {
        editableTaxLots.firstIndex { $0.id == id } ?? 0
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

private struct EditableTaxLot: Identifiable, Equatable {
    var id: UUID
    var sharesText: String
    var basisText: String

    init(id: UUID = UUID(), sharesText: String = "", basisText: String = "") {
        self.id = id
        self.sharesText = sharesText
        self.basisText = basisText
    }

    init(lot: TaxLot) {
        id = lot.id
        sharesText = lot.shares.inputString
        basisText = lot.averageCostBasis.inputString
    }

    var taxLot: TaxLot? {
        guard let shares = BuybackCalculator.parseDecimal(sharesText),
              let basis = BuybackCalculator.parseDecimal(basisText)
        else {
            return nil
        }

        let lot = TaxLot(id: id, shares: shares, averageCostBasis: basis)
        return lot.isValid ? lot : nil
    }
}

private struct TopChromeBlurBackground: View {
    let progress: Double

    var body: some View {
        let normalizedProgress = min(max(progress, 0), 1)
        let materialOpacity = min(1, normalizedProgress * 1.35)

        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.thickMaterial)
                .opacity(materialOpacity)

            Rectangle()
                .fill(Color(uiColor: .systemBackground).opacity(0.42 * normalizedProgress))

            LinearGradient(
                colors: [
                    Color.white.opacity(0.34 * normalizedProgress),
                    LiquidPalette.glassTint.opacity(0.10 * normalizedProgress),
                    Color(uiColor: .systemBackground).opacity(0.10 * normalizedProgress),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(Color.white.opacity(0.26 * normalizedProgress))
                .frame(height: 0.7)
                .blur(radius: 0.6)
                .opacity(normalizedProgress)
        }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.46),
                        .init(color: .black.opacity(0.62), location: 0.66),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

private struct SavedScenarioRow: View {
    let scenario: SavedBuybackScenario
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onLoad) {
                HStack(alignment: .center, spacing: 12) {
                    LiquidGlassIcon(icon: .bookmark, tint: LiquidPalette.accent, size: 34)

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
                LiquidGlassActionIcon(icon: .clear, tint: LiquidPalette.danger, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete saved scenario")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.18))
    }

    private var subtitle: String {
        let savedDate = scenario.savedAt.formatted(date: .abbreviated, time: .shortened)
        guard let calculation = scenario.calculation else {
            return "\(scenario.displaySymbol) • saved \(savedDate)"
        }

        return "\(scenario.displaySymbol) • \(calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode)) limit • saved \(savedDate)"
    }
}

private struct ScenarioComparisonRow: View {
    let scenario: SavedBuybackScenario
    let quote: MarketQuote?
    let calculation: BuybackCalculation?
    let alert: PriceAlert?
    let message: LookupMessage?
    let isRefreshing: Bool
    let onLoad: () -> Void
    let onFreeze: () -> Void
    let onEditFreeze: () -> Void
    let onUnfreeze: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                LiquidGlassIcon(icon: statusIcon, tint: statusTint, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let calculation {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    comparisonMetric("State", value: stateText, icon: statusIcon)
                    if scenario.isFrozen {
                        comparisonMetric("Frozen", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode), icon: .bookmark)
                        comparisonMetric("Now", value: currentPriceText, icon: .market)
                    } else {
                        comparisonMetric("Price", value: calculation.sellPrice.moneyString(currencyCode: calculation.currencyCode), icon: .price)
                    }
                    comparisonMetric("Limit", value: calculation.maximumBuybackPrice.moneyString(currencyCode: calculation.currencyCode), icon: .limit)
                    comparisonMetric("Drop", value: calculation.requiredDropPercent.compactPercentString, icon: .drop)
                    comparisonMetric("Alert", value: alertText, icon: alert?.isEnabled == true ? .alertArmed : .alert)
                }
            } else {
                StatusRow(message: .warning("Check saved scenario inputs."))
            }

            if let message {
                StatusRow(message: message)
            }

            HStack(spacing: 10) {
                if scenario.isFrozen {
                    Button(action: onEditFreeze) {
                        LiquidGlassActionIcon(icon: .edit, tint: LiquidPalette.muted, size: 38)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit frozen sell price")

                    Button(action: onUnfreeze) {
                        LiquidGlassActionIcon(icon: .toggleOff, tint: .secondary, size: 38)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unfreeze scenario")
                } else {
                    Button(action: onFreeze) {
                        LiquidGlassActionIcon(icon: .bookmark, tint: LiquidPalette.muted, size: 38)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Freeze scenario")
                }

                Button(action: onLoad) {
                    LiquidGlassActionIcon(icon: .selected, size: 38)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Load saved scenario")

                Button(role: .destructive, action: onDelete) {
                    LiquidGlassActionIcon(icon: .clear, tint: LiquidPalette.danger, size: 38)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete saved scenario")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.18))
    }

    private var subtitle: String {
        let savedDate = scenario.savedAt.formatted(date: .abbreviated, time: .shortened)
        let status = quote == nil ? "saved price" : "live price"
        return "\(scenario.displaySymbol) - \(stateText.lowercased()) - \(status) - saved \(savedDate)"
    }

    private var stateText: String {
        scenario.isBuybackReady(using: quote) ? "Ready" : scenario.trackingState.label
    }

    private var statusIcon: BuybackIconKind {
        if scenario.isBuybackReady(using: quote) {
            return .selected
        }

        if scenario.isFrozen {
            return .bookmark
        }

        return quote == nil ? .bookmark : .live
    }

    private var statusTint: Color {
        if scenario.isBuybackReady(using: quote) {
            return LiquidPalette.accent
        }

        if scenario.isFrozen {
            return LiquidPalette.muted
        }

        return quote == nil ? LiquidPalette.accent : LiquidPalette.accent
    }

    private var currentPriceText: String {
        guard let price = scenario.currentMarketPrice(using: quote) else {
            return "-"
        }

        let currencyCode = quote?.currencyCode ?? scenario.currencyCode
        return price.moneyString(currencyCode: currencyCode)
    }

    private var alertText: String {
        guard let alert, alert.isEnabled else {
            return "Off"
        }

        return alert.targetPrice.moneyString(currencyCode: alert.currencyCode)
    }

    private func comparisonMetric(_ title: String, value: String, icon: BuybackIconKind) -> some View {
        HStack(alignment: .center, spacing: 8) {
            BuybackIcon(icon, tint: LiquidPalette.accent)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .liquidCapsuleSurface(tint: LiquidPalette.accent.opacity(0.55))
    }
}

private struct AssetSuggestionRow: View {
    let asset: MarketAsset

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiquidGlassIcon(icon: .market, tint: LiquidPalette.accent, size: 34)

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
        .liquidCardBackground(tint: LiquidPalette.accent.opacity(0.22))
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
            BuybackIcon(manualPriceEnabled ? .edit : .live, tint: manualPriceEnabled ? LiquidPalette.muted : LiquidPalette.accent)
                .frame(width: 18, height: 18)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidCapsuleSurface(tint: manualPriceEnabled ? LiquidPalette.muted : LiquidPalette.accent)
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
            BuybackIcon(message.style == .warning ? .warning : .info, tint: message.style == .warning ? LiquidPalette.muted : .secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidCapsuleSurface(tint: message.style == .warning ? LiquidPalette.muted : LiquidPalette.accent)
    }
}

#Preview("Lookup") {
    ContentView()
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
