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
    }
}
