import Foundation
import XCTest

final class SharedFeatureTests: XCTestCase {
    func testLegacySavedScenarioDecodesAsWatchingWithDerivedBasis() throws {
        struct LegacyScenario: Codable {
            let id: UUID
            let name: String
            let savedAt: Date
            let assetQuery: String
            let selectedAsset: MarketAsset?
            let manualPriceEnabled: Bool
            let symbol: String
            let currencyCode: String
            let sellPrice: Double
            let gainPercent: Double
            let sharesToSell: Double
            let taxProfile: TaxProfile
            let taxRatePercent: Double
            let targetExtraSharesPercent: Double
            let sellFeeTotal: Double
            let buyFeeTotal: Double
            let slippagePercent: Double
        }

        let legacy = LegacyScenario(
            id: UUID(),
            name: "Legacy Apple",
            savedAt: Date(timeIntervalSince1970: 1_800_000_000),
            assetQuery: "AAPL",
            selectedAsset: nil,
            manualPriceEnabled: false,
            symbol: "AAPL",
            currencyCode: "USD",
            sellPrice: 200,
            gainPercent: 100,
            sharesToSell: 2,
            taxProfile: .custom,
            taxRatePercent: 20,
            targetExtraSharesPercent: 0,
            sellFeeTotal: 0,
            buyFeeTotal: 0,
            slippagePercent: 0
        )

        let data = try JSONEncoder().encode([legacy])
        let decoded = try JSONDecoder().decode([SavedBuybackScenario].self, from: data)
        let scenario = try XCTUnwrap(decoded.first)

        XCTAssertEqual(scenario.trackingState, .watching)
        XCTAssertFalse(scenario.isFrozen)
        XCTAssertFalse(scenario.isPinned)
        XCTAssertEqual(try XCTUnwrap(scenario.averageCostBasis), 100, accuracy: 0.0001)
        XCTAssertNil(scenario.frozenSellPrice)
    }

    func testFrozenScenarioRoundTripsAllTrackingFields() throws {
        let suiteName = "buybackCalculator.tracking.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let scenario = SavedBuybackScenario(
            id: UUID(),
            name: "Apple",
            savedAt: Date(timeIntervalSince1970: 1_800_000_000),
            assetQuery: "AAPL",
            selectedAsset: nil,
            manualPriceEnabled: false,
            symbol: "AAPL",
            currencyCode: "USD",
            sellPrice: 185,
            gainPercent: 85,
            sharesToSell: 3,
            averageCostBasis: 100,
            taxProfile: .custom,
            taxRatePercent: 20,
            targetExtraSharesPercent: 2.5,
            sellFeeTotal: 1,
            buyFeeTotal: 2,
            slippagePercent: 0.5,
            trackingState: .frozen,
            frozenSellPrice: 210,
            frozenCurrencyCode: "usd",
            frozenAt: Date(timeIntervalSince1970: 1_800_000_100),
            frozenQuoteTimestamp: Date(timeIntervalSince1970: 1_800_000_050)
        )

        SavedScenarioStorage.save([scenario], userDefaults: userDefaults)
        let loaded = try XCTUnwrap(SavedScenarioStorage.load(userDefaults: userDefaults).first)

        XCTAssertEqual(loaded, scenario)
        XCTAssertTrue(loaded.isFrozen)
        XCTAssertEqual(loaded.frozenCurrencyCode, "USD")
    }

    func testParseDecimalHandlesCommonLocalizedInputs() throws {
        XCTAssertEqual(try XCTUnwrap(BuybackCalculator.parseDecimal("$1,234.56")), 1_234.56, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(BuybackCalculator.parseDecimal("1.234,56 EUR")), 1_234.56, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(BuybackCalculator.parseDecimal("1 234,56")), 1_234.56, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(BuybackCalculator.parseDecimal("291.113", locale: Locale(identifier: "de_DE"))), 291.113, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(BuybackCalculator.parseDecimal("291.11", locale: Locale(identifier: "de_DE"))), 291.11, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(BuybackCalculator.parseDecimal("-12.5%")), -12.5, accuracy: 0.0001)
        XCTAssertNil(BuybackCalculator.parseDecimal("USD"))
    }

    func testInputStringUsesStableUngroupedDecimalFormat() {
        XCTAssertEqual(1_234.56.inputString, "1234.56")
        XCTAssertEqual(291.113.inputString, "291.113")
    }

    func testTaxLotDraftStorageRoundTripsMoreThanThreeLots() throws {
        let lots = [
            TaxLot(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID(), shares: 1, averageCostBasis: 100),
            TaxLot(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002") ?? UUID(), shares: 2, averageCostBasis: 120),
            TaxLot(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003") ?? UUID(), shares: 3, averageCostBasis: 140),
            TaxLot(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004") ?? UUID(), shares: 4, averageCostBasis: 160)
        ]

        let encoded = TaxLotDraftStorage.encode(lots)
        let decoded = TaxLotDraftStorage.decode(encoded)

        XCTAssertEqual(decoded, lots)
        XCTAssertEqual(TaxLot.totalShares(decoded), 10, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(TaxLot.weightedAverageCostBasis(decoded)), 140, accuracy: 0.0001)
    }

    func testTaxLotDraftStorageMigratesLegacyThreeLotFields() {
        let lots = TaxLotDraftStorage.legacyLots(
            lot1Shares: "1",
            lot1Basis: "100",
            lot2Shares: "2,5",
            lot2Basis: "120,25",
            lot3Shares: "",
            lot3Basis: ""
        )

        XCTAssertEqual(lots.count, 2)
        XCTAssertEqual(lots[0].shares, 1, accuracy: 0.0001)
        XCTAssertEqual(lots[1].shares, 2.5, accuracy: 0.0001)
        XCTAssertEqual(lots[1].averageCostBasis, 120.25, accuracy: 0.0001)
    }

    func testSavedScenarioCalculationUsesLiveQuoteWhenAvailable() throws {
        let scenario = SavedBuybackScenario(
            id: UUID(),
            name: "Apple",
            savedAt: .now,
            assetQuery: "AAPL",
            selectedAsset: nil,
            manualPriceEnabled: false,
            symbol: "AAPL",
            currencyCode: "USD",
            sellPrice: 100,
            gainPercent: 100,
            sharesToSell: 2,
            averageCostBasis: 50,
            taxProfile: .custom,
            taxRatePercent: 20,
            targetExtraSharesPercent: 0,
            sellFeeTotal: 0,
            buyFeeTotal: 0,
            slippagePercent: 0
        )
        let quote = MarketQuote(
            symbol: "AAPL",
            price: 200,
            currencyCode: "USD",
            timestamp: .now,
            source: .finnhub,
            isStale: false,
            statusMessage: nil
        )

        let fallbackCalculation = try XCTUnwrap(scenario.calculation(using: nil))
        let liveCalculation = try XCTUnwrap(scenario.calculation(using: quote))

        XCTAssertEqual(fallbackCalculation.sellPrice, 100, accuracy: 0.0001)
        XCTAssertEqual(liveCalculation.sellPrice, 200, accuracy: 0.0001)
        XCTAssertEqual(liveCalculation.averageCostBasis, 50, accuracy: 0.0001)
        XCTAssertEqual(liveCalculation.maximumBuybackPrice, 170, accuracy: 0.0001)
    }

    func testFrozenScenarioIgnoresLiveQuoteAsSellPriceAndReportsReadiness() throws {
        let scenario = SavedBuybackScenario(
            id: UUID(),
            name: "Apple",
            savedAt: .now,
            assetQuery: "AAPL",
            selectedAsset: nil,
            manualPriceEnabled: false,
            symbol: "AAPL",
            currencyCode: "USD",
            sellPrice: 100,
            gainPercent: 100,
            sharesToSell: 2,
            averageCostBasis: 50,
            taxProfile: .custom,
            taxRatePercent: 20,
            targetExtraSharesPercent: 0,
            sellFeeTotal: 0,
            buyFeeTotal: 0,
            slippagePercent: 0,
            trackingState: .frozen,
            frozenSellPrice: 150,
            frozenCurrencyCode: "USD",
            frozenAt: .now
        )
        let quote = MarketQuote(
            symbol: "AAPL",
            price: 90,
            currencyCode: "USD",
            timestamp: .now,
            source: .finnhub,
            isStale: false,
            statusMessage: nil
        )

        let calculation = try XCTUnwrap(scenario.calculation(using: quote))

        XCTAssertEqual(calculation.sellPrice, 150, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(scenario.currentMarketPrice(using: quote)), 90, accuracy: 0.0001)
        XCTAssertEqual(calculation.maximumBuybackPrice, 130, accuracy: 0.0001)
        XCTAssertTrue(scenario.isBuybackReady(using: quote))
    }

    func testScenarioMutationHelpersFreezeUnfreezeOnlyMatchingScenario() throws {
        let suiteName = "buybackCalculator.mutations.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let targetID = UUID()
        let otherID = UUID()
        let scenarios = [
            SavedBuybackScenario(
                id: targetID,
                name: "Apple",
                savedAt: .now,
                assetQuery: "AAPL",
                selectedAsset: nil,
                manualPriceEnabled: false,
                symbol: "AAPL",
                currencyCode: "USD",
                sellPrice: 100,
                gainPercent: 100,
                sharesToSell: 1,
                averageCostBasis: 50,
                taxRatePercent: 27,
                targetExtraSharesPercent: 0,
                sellFeeTotal: 0,
                buyFeeTotal: 0,
                slippagePercent: 0
            ),
            SavedBuybackScenario(
                id: otherID,
                name: "SAP",
                savedAt: .now.addingTimeInterval(-1),
                assetQuery: "SAP.DE",
                selectedAsset: nil,
                manualPriceEnabled: false,
                symbol: "SAP.DE",
                currencyCode: "EUR",
                sellPrice: 200,
                gainPercent: 100,
                sharesToSell: 1,
                averageCostBasis: 100,
                taxRatePercent: 27,
                targetExtraSharesPercent: 0,
                sellFeeTotal: 0,
                buyFeeTotal: 0,
                slippagePercent: 0
            )
        ]
        SavedScenarioStorage.save(scenarios, userDefaults: userDefaults)

        XCTAssertTrue(
            SavedScenarioStorage.freezeScenario(
                id: targetID,
                sellPrice: 123,
                currencyCode: "usd",
                quoteTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
                userDefaults: userDefaults
            )
        )
        var loaded = SavedScenarioStorage.load(userDefaults: userDefaults)
        let frozen = try XCTUnwrap(loaded.first { $0.id == targetID })
        let untouched = try XCTUnwrap(loaded.first { $0.id == otherID })
        XCTAssertTrue(frozen.isFrozen)
        XCTAssertEqual(try XCTUnwrap(frozen.frozenSellPrice), 123, accuracy: 0.0001)
        XCTAssertEqual(untouched.trackingState, .watching)

        XCTAssertTrue(SavedScenarioStorage.unfreezeScenario(id: targetID, userDefaults: userDefaults))
        loaded = SavedScenarioStorage.load(userDefaults: userDefaults)
        let unfrozen = try XCTUnwrap(loaded.first { $0.id == targetID })
        XCTAssertEqual(unfrozen.trackingState, .watching)
        XCTAssertNil(unfrozen.frozenSellPrice)
    }

    func testSavedScenarioPinningCapsAtTenAndOrdersWidgetRows() throws {
        let suiteName = "buybackCalculator.pins.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let ids = (0..<11).map { _ in UUID() }
        let scenarios = ids.enumerated().map { index, id in
            makeScenario(
                id: id,
                symbol: "PIN\(index)",
                savedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        SavedScenarioStorage.save(scenarios, userDefaults: userDefaults)
        XCTAssertTrue(SavedScenarioStorage.widgetScenarios(from: SavedScenarioStorage.load(userDefaults: userDefaults)).isEmpty)

        for index in 0..<SavedScenarioStorage.maximumPinnedScenarios {
            XCTAssertTrue(
                SavedScenarioStorage.pinScenario(
                    id: ids[index],
                    now: baseDate.addingTimeInterval(TimeInterval(index)),
                    userDefaults: userDefaults
                )
            )
        }

        XCTAssertFalse(
            SavedScenarioStorage.pinScenario(
                id: ids[10],
                now: baseDate.addingTimeInterval(10),
                userDefaults: userDefaults
            )
        )

        var loaded = SavedScenarioStorage.load(userDefaults: userDefaults)
        var pinned = SavedScenarioStorage.pinnedScenarios(from: loaded)
        XCTAssertEqual(pinned.count, SavedScenarioStorage.maximumPinnedScenarios)
        XCTAssertEqual(pinned.first?.id, ids[9])
        XCTAssertEqual(SavedScenarioStorage.widgetScenarios(from: loaded).map(\.id), pinned.map(\.id))

        XCTAssertTrue(SavedScenarioStorage.unpinScenario(id: ids[0], userDefaults: userDefaults))
        XCTAssertTrue(
            SavedScenarioStorage.pinScenario(
                id: ids[10],
                now: baseDate.addingTimeInterval(20),
                userDefaults: userDefaults
            )
        )

        loaded = SavedScenarioStorage.load(userDefaults: userDefaults)
        pinned = SavedScenarioStorage.pinnedScenarios(from: loaded)
        XCTAssertEqual(pinned.count, SavedScenarioStorage.maximumPinnedScenarios)
        XCTAssertEqual(pinned.first?.id, ids[10])
        XCTAssertFalse(try XCTUnwrap(loaded.first { $0.id == ids[0] }).isPinned)
    }

    func testTaxLotScenarioUsesWeightedBasisWhenWatchingAndFrozen() throws {
        let scenario = SavedBuybackScenario(
            id: UUID(),
            name: "Lots",
            savedAt: .now,
            assetQuery: "MSFT",
            selectedAsset: nil,
            manualPriceEnabled: false,
            symbol: "MSFT",
            currencyCode: "USD",
            sellPrice: 120,
            gainPercent: 100,
            sharesToSell: 99,
            averageCostBasis: 5,
            taxProfile: .custom,
            taxRatePercent: 20,
            targetExtraSharesPercent: 0,
            sellFeeTotal: 0,
            buyFeeTotal: 0,
            slippagePercent: 0,
            taxLotsEnabled: true,
            taxLots: [
                TaxLot(shares: 1, averageCostBasis: 100),
                TaxLot(shares: 3, averageCostBasis: 140)
            ],
            trackingState: .frozen,
            frozenSellPrice: 200,
            frozenCurrencyCode: "USD"
        )
        let quote = MarketQuote(
            symbol: "MSFT",
            price: 150,
            currencyCode: "USD",
            timestamp: .now,
            source: .finnhub,
            isStale: false,
            statusMessage: nil
        )

        let calculation = try XCTUnwrap(scenario.calculation(using: quote))

        XCTAssertEqual(calculation.sharesToSell, 4, accuracy: 0.0001)
        XCTAssertEqual(calculation.averageCostBasis, 130, accuracy: 0.0001)
        XCTAssertEqual(calculation.sellPrice, 200, accuracy: 0.0001)
    }

    func testPriceAlertStorageMigratesLegacyDefaults() throws {
        let currentName = "buybackCalculator.alerts.current.\(UUID().uuidString)"
        let legacyName = "buybackCalculator.alerts.legacy.\(UUID().uuidString)"
        let currentDefaults = try XCTUnwrap(UserDefaults(suiteName: currentName))
        let legacyDefaults = try XCTUnwrap(UserDefaults(suiteName: legacyName))
        defer {
            currentDefaults.removePersistentDomain(forName: currentName)
            legacyDefaults.removePersistentDomain(forName: legacyName)
        }

        let alert = PriceAlert(symbol: "AAPL", targetPrice: 140, currencyCode: "USD", isEnabled: true, lastTriggeredAt: nil)
        PriceAlertStorage.save([alert], userDefaults: legacyDefaults)

        let loaded = PriceAlertStorage.load(userDefaults: currentDefaults, legacyUserDefaults: legacyDefaults)

        XCTAssertEqual(loaded, [alert])
        XCTAssertNotNil(currentDefaults.data(forKey: PriceAlertStorage.storageKey))
    }

    func testPriceAlertEvaluatorTriggersAndThrottles() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let alert = PriceAlert(symbol: "AAPL", targetPrice: 140, currencyCode: "USD", isEnabled: true, lastTriggeredAt: nil)
        let recentlyTriggered = PriceAlert(
            symbol: "MSFT",
            targetPrice: 300,
            currencyCode: "USD",
            isEnabled: true,
            lastTriggeredAt: now.addingTimeInterval(-60 * 30)
        )
        let oldTrigger = PriceAlert(
            symbol: "SAP.DE",
            targetPrice: 210,
            currencyCode: "EUR",
            isEnabled: true,
            lastTriggeredAt: now.addingTimeInterval(-60 * 60 * 7)
        )

        XCTAssertTrue(PriceAlertEvaluator.shouldTrigger(alert, price: 139, now: now))
        XCTAssertFalse(PriceAlertEvaluator.shouldTrigger(alert, price: 141, now: now))
        XCTAssertFalse(PriceAlertEvaluator.shouldTrigger(recentlyTriggered, price: 299, now: now))
        XCTAssertTrue(PriceAlertEvaluator.shouldTrigger(oldTrigger, price: 200, now: now))
        XCTAssertEqual(PriceAlertEvaluator.triggerIndex(in: [alert, recentlyTriggered, oldTrigger], symbol: "SAP.DE", price: 200, now: now), 2)
    }

    func testTaxProfileAssumptionTextIsAvailable() {
        for profile in TaxProfile.allCases {
            XCTAssertFalse(profile.assumptionSummary.isEmpty)
            XCTAssertFalse(profile.assumptionDetails.isEmpty)
        }
    }

    func testAPIKeyValidationAcceptsOnlyUsableNonPlaceholderValues() throws {
        XCTAssertEqual(
            try APIKeyValidator.validatedAPIKey(" abc-DEF_123.456 ", for: .finnhub),
            "abc-DEF_123.456"
        )
        XCTAssertNil(try APIKeyValidator.validatedAPIKey("   ", for: .openFIGI))
        XCTAssertNil(APIKeyValidator.sanitizedAPIKey("$(FINNHUB_API_KEY)"))
        XCTAssertNil(APIKeyValidator.sanitizedAPIKey("your_finnhub_key"))
        XCTAssertNil(APIKeyValidator.sanitizedAPIKey("abc 123"))

        XCTAssertThrowsError(try APIKeyValidator.validatedAPIKey("abc 123", for: .finnhub)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Finnhub API key is invalid"))
        }
    }

    func testMarketDataClientFactoryAcceptsExplicitFinnhubKeyWithoutSavedKeys() {
        XCTAssertNotNil(
            MarketDataClientFactory.make(
                finnhubAPIKey: "finnhub-token_123.abc",
                openFIGIAPIKey: nil,
                includeSavedKeys: false
            )
        )

        XCTAssertNil(
            MarketDataClientFactory.make(
                finnhubAPIKey: "   ",
                openFIGIAPIKey: nil,
                includeSavedKeys: false
            )
        )
    }

    func testMarketQuoteCacheThrottlesRefreshesAndFallsBackToCachedQuote() async throws {
        let suiteName = "buybackCalculator.quoteCache.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = MarketAsset(symbol: "AAPL", name: "Apple Inc.", currencyCode: "USD", source: .finnhub)
        let firstQuote = MarketQuote(
            symbol: "AAPL",
            price: 100,
            currencyCode: "USD",
            timestamp: now,
            source: .finnhub,
            isStale: false,
            statusMessage: nil
        )
        let secondQuote = MarketQuote(
            symbol: "AAPL",
            price: 120,
            currencyCode: "USD",
            timestamp: now.addingTimeInterval(301),
            source: .finnhub,
            isStale: false,
            statusMessage: nil
        )
        let client = StubMarketDataClient(quotes: [firstQuote, secondQuote])

        let liveResult = await MarketQuoteCache.refreshQuote(for: asset, client: client, now: now, userDefaults: userDefaults)
        XCTAssertEqual(liveResult.status, .live)
        XCTAssertEqual(liveResult.quote, firstQuote)
        var quoteRequestCount = await client.quoteRequestCount
        XCTAssertEqual(quoteRequestCount, 1)

        let cachedResult = await MarketQuoteCache.refreshQuote(
            for: asset,
            client: client,
            now: now.addingTimeInterval(60),
            userDefaults: userDefaults
        )
        XCTAssertEqual(cachedResult.status, .cached(nextRefreshAt: now.addingTimeInterval(MarketQuoteCache.minimumRefreshInterval)))
        XCTAssertEqual(cachedResult.quote, firstQuote)
        quoteRequestCount = await client.quoteRequestCount
        XCTAssertEqual(quoteRequestCount, 1)

        let refreshedResult = await MarketQuoteCache.refreshQuote(
            for: asset,
            client: client,
            now: now.addingTimeInterval(MarketQuoteCache.minimumRefreshInterval + 1),
            userDefaults: userDefaults
        )
        XCTAssertEqual(refreshedResult.status, .live)
        XCTAssertEqual(refreshedResult.quote, secondQuote)
        quoteRequestCount = await client.quoteRequestCount
        XCTAssertEqual(quoteRequestCount, 2)

        let failingClient = StubMarketDataClient(error: MarketDataError.rateLimited)
        let fallbackResult = await MarketQuoteCache.refreshQuote(
            for: asset,
            client: failingClient,
            now: now.addingTimeInterval(MarketQuoteCache.minimumRefreshInterval * 2 + 2),
            userDefaults: userDefaults
        )

        XCTAssertEqual(fallbackResult.quote, secondQuote)
        if case .cachedFallback(let reason) = fallbackResult.status {
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("limit"))
        } else {
            XCTFail("Expected cached fallback after a failed refresh.")
        }
    }

    private func makeScenario(
        id: UUID = UUID(),
        symbol: String = "AAPL",
        savedAt: Date = .now,
        pinnedAt: Date? = nil
    ) -> SavedBuybackScenario {
        SavedBuybackScenario(
            id: id,
            name: symbol,
            savedAt: savedAt,
            assetQuery: symbol,
            selectedAsset: nil,
            manualPriceEnabled: false,
            symbol: symbol,
            currencyCode: "USD",
            sellPrice: 100,
            gainPercent: 100,
            sharesToSell: 1,
            averageCostBasis: 50,
            taxRatePercent: 27,
            targetExtraSharesPercent: 0,
            sellFeeTotal: 0,
            buyFeeTotal: 0,
            slippagePercent: 0,
            pinnedAt: pinnedAt
        )
    }
}

private actor StubMarketDataClient: MarketDataClient {
    private var quotes: [MarketQuote]
    private let error: Error?
    private(set) var quoteRequestCount = 0

    init(quotes: [MarketQuote] = [], error: Error? = nil) {
        self.quotes = quotes
        self.error = error
    }

    func searchAssets(query: String) async throws -> [MarketAsset] {
        []
    }

    func quote(for asset: MarketAsset) async throws -> MarketQuote {
        quoteRequestCount += 1
        if let error {
            throw error
        }

        guard !quotes.isEmpty else {
            throw MarketDataError.quoteUnavailable
        }

        return quotes.removeFirst()
    }
}
