import XCTest

final class BuybackCalculationTests: XCTestCase {
    func testGainDrivenCalculationDerivesCostBasis() throws {
        let calculation = try XCTUnwrap(
            BuybackCalculator.calculate(
                symbol: "aapl",
                sellPrice: 200,
                gainAtSellPercent: 100,
                sharesToSell: 2,
                taxRatePercent: 27,
                targetExtraSharesPercent: 2.5,
                currencyCode: "usd"
            )
        )

        XCTAssertEqual(calculation.symbol, "AAPL")
        XCTAssertEqual(calculation.currencyCode, "USD")
        XCTAssertEqual(calculation.averageCostBasis, 100, accuracy: 0.0001)
        XCTAssertEqual(calculation.costBasisTotal, 200, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxableGainTotal, 200, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxAmount, 54, accuracy: 0.0001)
        XCTAssertEqual(calculation.afterTaxCash, 346, accuracy: 0.0001)
        XCTAssertEqual(calculation.targetShareCount, 2.05, accuracy: 0.0001)
        XCTAssertEqual(calculation.maximumBuybackPrice, 168.7805, accuracy: 0.0001)
    }

    func testGainDrivenCalculationRejectsInvalidGain() {
        XCTAssertNil(
            BuybackCalculator.calculate(
                sellPrice: 200,
                gainAtSellPercent: -100
            )
        )
        XCTAssertNil(
            BuybackCalculator.calculate(
                sellPrice: 200,
                gainAtSellPercent: -120
            )
        )
    }

    func testCurrencyCodeFallsBackWhenInvalid() throws {
        let calculation = try XCTUnwrap(
            BuybackCalculator.calculate(
                sellPrice: 100,
                gainAtSellPercent: 25,
                currencyCode: "not-a-code"
            )
        )

        XCTAssertEqual(calculation.currencyCode, BuybackCalculator.defaultCurrencyCode)
    }

    func testPositionBasedCalculationStillUsesExistingTaxAndTargetMath() throws {
        let calculation = try XCTUnwrap(
            BuybackCalculator.calculate(
                symbol: "MSFT",
                sharesToSell: 10,
                averageCostBasis: 125,
                sellPrice: 185,
                taxRatePercent: 27,
                targetExtraSharesPercent: 2.5,
                currencyCode: "EUR"
            )
        )

        XCTAssertEqual(calculation.gainAtSellPercent, 48, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxAmount, 162, accuracy: 0.0001)
        XCTAssertEqual(calculation.afterTaxCash, 1688, accuracy: 0.0001)
        XCTAssertEqual(calculation.maximumBuybackPrice, 164.6829, accuracy: 0.0001)
        XCTAssertEqual(calculation.currencyCode, "EUR")
    }

    func testFeesAndSlippageReduceBuybackLimit() throws {
        let calculation = try XCTUnwrap(
            BuybackCalculator.calculate(
                symbol: "AAPL",
                sharesToSell: 10,
                averageCostBasis: 100,
                sellPrice: 200,
                taxProfile: .custom,
                taxRatePercent: 25,
                targetExtraSharesPercent: 5,
                sellFeeTotal: 10,
                buyFeeTotal: 5,
                slippagePercent: 1,
                currencyCode: "USD"
            )
        )

        XCTAssertEqual(calculation.netSaleProceeds, 1_990, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxableGainTotal, 990, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxAmount, 247.5, accuracy: 0.0001)
        XCTAssertEqual(calculation.cashAvailableForBuyback, 1_737.5, accuracy: 0.0001)
        XCTAssertEqual(calculation.maximumBuybackPrice, 163.8378, accuracy: 0.0001)
    }

    func testRejectsNegativeFeesAndSlippage() {
        XCTAssertNil(
            BuybackCalculator.calculate(
                sellPrice: 100,
                gainAtSellPercent: 20,
                sellFeeTotal: -1
            )
        )
        XCTAssertNil(
            BuybackCalculator.calculate(
                sellPrice: 100,
                gainAtSellPercent: 20,
                buyFeeTotal: -1
            )
        )
        XCTAssertNil(
            BuybackCalculator.calculate(
                sellPrice: 100,
                gainAtSellPercent: 20,
                slippagePercent: -0.1
            )
        )
        XCTAssertNil(
            BuybackCalculator.calculate(
                sellPrice: 100,
                gainAtSellPercent: 20,
                taxProfile: .custom,
                taxRatePercent: 101
            )
        )
    }

    func testTaxProfileOverridesCustomRateAndTracksTaxCurrency() throws {
        let calculation = try XCTUnwrap(
            BuybackCalculator.calculate(
                symbol: "AAPL",
                sharesToSell: 1,
                averageCostBasis: 100,
                sellPrice: 200,
                taxProfile: .usLongTerm,
                taxRatePercent: 999,
                taxCurrencyCode: "EUR",
                fxRateToTaxCurrency: 0.9,
                targetExtraSharesPercent: 2.5,
                currencyCode: "USD"
            )
        )

        XCTAssertEqual(calculation.taxRatePercent, 15, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxableGainInTaxCurrency, 90, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxAmountInTaxCurrency, 13.5, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxAmount, 15, accuracy: 0.0001)
        XCTAssertEqual(calculation.maximumBuybackPrice, 180.4878, accuracy: 0.0001)
    }

    func testWeightedTaxLotsProduceAverageCostBasis() throws {
        let lots = [
            TaxLot(shares: 2, averageCostBasis: 100),
            TaxLot(shares: 3, averageCostBasis: 140)
        ]

        XCTAssertEqual(TaxLot.totalShares(lots), 5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(TaxLot.weightedAverageCostBasis(lots)), 124, accuracy: 0.0001)

        let calculation = try XCTUnwrap(
            BuybackCalculator.calculate(
                symbol: "MSFT",
                sharesToSell: TaxLot.totalShares(lots),
                averageCostBasis: try XCTUnwrap(TaxLot.weightedAverageCostBasis(lots)),
                sellPrice: 200,
                taxProfile: .custom,
                taxRatePercent: 20,
                targetExtraSharesPercent: 0
            )
        )

        XCTAssertEqual(calculation.costBasisTotal, 620, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxableGainTotal, 380, accuracy: 0.0001)
        XCTAssertEqual(calculation.taxAmount, 76, accuracy: 0.0001)
        XCTAssertEqual(calculation.maximumBuybackPrice, 184.8, accuracy: 0.0001)
    }

    func testSavedScenarioStorageRoundTripsPortfolioSource() throws {
        let suiteName = "buybackCalculator.tests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let scenario = SavedBuybackScenario(
            id: UUID(uuidString: "A1E06611-FD3E-49D9-8F3B-B233B439B964") ?? UUID(),
            name: "Apple",
            savedAt: Date(timeIntervalSince1970: 1_800_000_000),
            assetQuery: "AAPL",
            selectedAsset: MarketAsset(
                symbol: "AAPL",
                name: "Apple Inc.",
                exchange: "US",
                currencyCode: "USD",
                source: .finnhub
            ),
            manualPriceEnabled: false,
            symbol: "AAPL",
            currencyCode: "USD",
            sellPrice: 185,
            gainPercent: 463.10,
            sharesToSell: 1,
            taxRatePercent: 27,
            targetExtraSharesPercent: 2.5,
            sellFeeTotal: 0,
            buyFeeTotal: 0,
            slippagePercent: 0
        )

        SavedScenarioStorage.save([scenario], userDefaults: userDefaults)

        let loaded = SavedScenarioStorage.load(userDefaults: userDefaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], scenario)
        let calculation = try XCTUnwrap(loaded[0].calculation)
        XCTAssertEqual(calculation.maximumBuybackPrice, 140.4103, accuracy: 0.0001)
    }
}
