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
}
