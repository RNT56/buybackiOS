import Foundation

struct BuybackInputs: Codable, Equatable, Sendable {
    var symbol: String
    var sharesToSell: Double
    var averageCostBasis: Double
    var sellPrice: Double
    var taxRatePercent: Double
    var targetExtraSharesPercent: Double
    var sellFeeTotal: Double
    var buyFeeTotal: Double
    var slippagePercent: Double
    var currencyCode: String

    init(
        symbol: String = BuybackCalculator.defaultSymbol,
        sharesToSell: Double = BuybackCalculator.defaultSharesToSell,
        averageCostBasis: Double = BuybackCalculator.defaultAverageCostBasis,
        sellPrice: Double = BuybackCalculator.defaultSellPrice,
        taxRatePercent: Double = BuybackCalculator.fixedTaxRatePercent,
        targetExtraSharesPercent: Double = BuybackCalculator.fixedTargetExtraSharesPercent,
        sellFeeTotal: Double = BuybackCalculator.defaultSellFeeTotal,
        buyFeeTotal: Double = BuybackCalculator.defaultBuyFeeTotal,
        slippagePercent: Double = BuybackCalculator.defaultSlippagePercent,
        currencyCode: String = BuybackCalculator.defaultCurrencyCode
    ) {
        self.symbol = symbol.normalizedStockSymbol
        self.sharesToSell = sharesToSell
        self.averageCostBasis = averageCostBasis
        self.sellPrice = sellPrice
        self.taxRatePercent = taxRatePercent
        self.targetExtraSharesPercent = targetExtraSharesPercent
        self.sellFeeTotal = sellFeeTotal
        self.buyFeeTotal = buyFeeTotal
        self.slippagePercent = slippagePercent
        self.currencyCode = currencyCode.normalizedCurrencyCode
    }
}

struct BuybackCalculation: Equatable, Identifiable, Sendable {
    var id: String {
        [
            symbol,
            sharesToSell.keyString,
            averageCostBasis.keyString,
            sellPrice.keyString,
            taxRatePercent.keyString,
            targetExtraSharesPercent.keyString,
            sellFeeTotal.keyString,
            buyFeeTotal.keyString,
            slippagePercent.keyString,
            currencyCode
        ].joined(separator: "-")
    }

    let symbol: String
    let sharesToSell: Double
    let averageCostBasis: Double
    let sellPrice: Double
    let gainAtSellPercent: Double
    let taxRatePercent: Double
    let targetExtraSharesPercent: Double
    let sellFeeTotal: Double
    let buyFeeTotal: Double
    let slippagePercent: Double
    let currencyCode: String

    let costBasisTotal: Double
    let grossProceeds: Double
    let netSaleProceeds: Double
    let taxableGainPerShare: Double
    let taxableGainTotal: Double
    let taxAmount: Double
    let afterTaxCash: Double
    let afterTaxCashPerShare: Double
    let cashAvailableForBuyback: Double
    let targetSharesPerSoldShare: Double
    let targetShareCount: Double
    let extraShareTarget: Double
    let maximumBuybackPrice: Double
    let requiredDropPercent: Double

    var retainedCashPerSoldShare: Double {
        sellPrice - maximumBuybackPrice
    }

    var costBasis: Double {
        averageCostBasis
    }

    var buybackDiscountRatio: Double {
        guard sellPrice > 0 else { return 0 }
        return maximumBuybackPrice / sellPrice
    }

    var targetSharesLabel: String {
        targetSharesPerSoldShare.shareString
    }

    var headline: String {
        "\(displaySymbol) buy-back at \(maximumBuybackPrice.moneyString(currencyCode: currencyCode))"
    }

    var displaySymbol: String {
        symbol.isEmpty ? "STOCK" : symbol
    }

    var summary: String {
        "Sell \(sharesToSell.shareString) \(displaySymbol) at \(sellPrice.moneyString(currencyCode: currencyCode)), then buy back at or below \(maximumBuybackPrice.moneyString(currencyCode: currencyCode)) to target \(targetShareCount.shareString) shares after tax."
    }
}

enum BuybackCalculator {
    static let defaultSymbol = "AAPL"
    static let defaultSharesToSell: Double = 10
    static let defaultAverageCostBasis: Double = 125
    static let defaultSellPrice: Double = 185
    static let defaultCurrencyCode = "USD"
    static let fixedTaxRatePercent: Double = 27
    static let fixedTargetExtraSharesPercent: Double = 2.5
    static let defaultSellFeeTotal: Double = 0
    static let defaultBuyFeeTotal: Double = 0
    static let defaultSlippagePercent: Double = 0

    static var defaultInputs: BuybackInputs {
        BuybackInputs()
    }

    static var sampleCalculation: BuybackCalculation {
        calculate(inputs: defaultInputs)!
    }

    static func calculate(inputs: BuybackInputs) -> BuybackCalculation? {
        calculate(
            symbol: inputs.symbol,
            sharesToSell: inputs.sharesToSell,
            averageCostBasis: inputs.averageCostBasis,
            sellPrice: inputs.sellPrice,
            taxRatePercent: inputs.taxRatePercent,
            targetExtraSharesPercent: inputs.targetExtraSharesPercent,
            sellFeeTotal: inputs.sellFeeTotal,
            buyFeeTotal: inputs.buyFeeTotal,
            slippagePercent: inputs.slippagePercent,
            currencyCode: inputs.currencyCode
        )
    }

    static func calculate(
        symbol: String,
        sharesToSell: Double,
        averageCostBasis: Double,
        sellPrice: Double,
        taxRatePercent: Double = fixedTaxRatePercent,
        targetExtraSharesPercent: Double = fixedTargetExtraSharesPercent,
        sellFeeTotal: Double = defaultSellFeeTotal,
        buyFeeTotal: Double = defaultBuyFeeTotal,
        slippagePercent: Double = defaultSlippagePercent,
        currencyCode: String = defaultCurrencyCode
    ) -> BuybackCalculation? {
        guard sharesToSell.isFinite,
              averageCostBasis.isFinite,
              sellPrice.isFinite,
              taxRatePercent.isFinite,
              targetExtraSharesPercent.isFinite,
              sellFeeTotal.isFinite,
              buyFeeTotal.isFinite,
              slippagePercent.isFinite,
              sharesToSell > 0,
              averageCostBasis > 0,
              sellPrice > 0,
              taxRatePercent >= 0,
              taxRatePercent <= 100,
              targetExtraSharesPercent >= 0,
              sellFeeTotal >= 0,
              buyFeeTotal >= 0,
              slippagePercent >= 0
        else {
            return nil
        }

        let normalizedSymbol = symbol.normalizedStockSymbol
        let normalizedCurrencyCode = currencyCode.normalizedCurrencyCode
        let gainAtSellPercent = ((sellPrice - averageCostBasis) / averageCostBasis) * 100
        let costBasisTotal = averageCostBasis * sharesToSell
        let grossProceeds = sellPrice * sharesToSell
        let netSaleProceeds = grossProceeds - sellFeeTotal
        let taxableGainTotal = max(0, netSaleProceeds - costBasisTotal)
        let taxableGainPerShare = taxableGainTotal / sharesToSell
        let taxAmount = taxableGainTotal * taxRatePercent / 100
        let afterTaxCash = netSaleProceeds - taxAmount
        let afterTaxCashPerShare = afterTaxCash / sharesToSell
        let cashAvailableForBuyback = max(0, afterTaxCash - buyFeeTotal)
        let targetSharesPerSoldShare = 1 + targetExtraSharesPercent / 100
        let targetShareCount = sharesToSell * targetSharesPerSoldShare
        let slippageMultiplier = 1 + slippagePercent / 100
        let maximumBuybackPrice = cashAvailableForBuyback / targetShareCount / slippageMultiplier
        let requiredDropPercent = ((sellPrice - maximumBuybackPrice) / sellPrice) * 100

        return BuybackCalculation(
            symbol: normalizedSymbol,
            sharesToSell: sharesToSell,
            averageCostBasis: averageCostBasis,
            sellPrice: sellPrice,
            gainAtSellPercent: gainAtSellPercent,
            taxRatePercent: taxRatePercent,
            targetExtraSharesPercent: targetExtraSharesPercent,
            sellFeeTotal: sellFeeTotal,
            buyFeeTotal: buyFeeTotal,
            slippagePercent: slippagePercent,
            currencyCode: normalizedCurrencyCode,
            costBasisTotal: costBasisTotal,
            grossProceeds: grossProceeds,
            netSaleProceeds: netSaleProceeds,
            taxableGainPerShare: taxableGainPerShare,
            taxableGainTotal: taxableGainTotal,
            taxAmount: taxAmount,
            afterTaxCash: afterTaxCash,
            afterTaxCashPerShare: afterTaxCashPerShare,
            cashAvailableForBuyback: cashAvailableForBuyback,
            targetSharesPerSoldShare: targetSharesPerSoldShare,
            targetShareCount: targetShareCount,
            extraShareTarget: targetShareCount - sharesToSell,
            maximumBuybackPrice: maximumBuybackPrice,
            requiredDropPercent: requiredDropPercent
        )
    }

    static func calculate(
        symbol: String = defaultSymbol,
        sellPrice: Double,
        gainAtSellPercent: Double,
        sharesToSell: Double = 1,
        taxRatePercent: Double = fixedTaxRatePercent,
        targetExtraSharesPercent: Double = fixedTargetExtraSharesPercent,
        sellFeeTotal: Double = defaultSellFeeTotal,
        buyFeeTotal: Double = defaultBuyFeeTotal,
        slippagePercent: Double = defaultSlippagePercent,
        currencyCode: String = defaultCurrencyCode
    ) -> BuybackCalculation? {
        guard gainAtSellPercent.isFinite,
              gainAtSellPercent > -100
        else {
            return nil
        }
        let costBasis = sellPrice / (1 + gainAtSellPercent / 100)
        return calculate(
            symbol: symbol,
            sharesToSell: sharesToSell,
            averageCostBasis: costBasis,
            sellPrice: sellPrice,
            taxRatePercent: taxRatePercent,
            targetExtraSharesPercent: targetExtraSharesPercent,
            sellFeeTotal: sellFeeTotal,
            buyFeeTotal: buyFeeTotal,
            slippagePercent: slippagePercent,
            currencyCode: currencyCode
        )
    }

    static func parseDecimal(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    static func validationMessage(inputs: BuybackInputs) -> String? {
        guard !inputs.symbol.normalizedStockSymbol.isEmpty else {
            return "Enter a stock symbol."
        }

        guard inputs.sharesToSell > 0 else {
            return "Shares to sell must be greater than 0."
        }

        guard inputs.averageCostBasis > 0 else {
            return "Average cost basis must be greater than 0."
        }

        guard inputs.sellPrice > 0 else {
            return "Planned sale price must be greater than 0."
        }

        guard inputs.taxRatePercent >= 0, inputs.taxRatePercent <= 100 else {
            return "Tax rate must be between 0% and 100%."
        }

        guard inputs.targetExtraSharesPercent >= 0 else {
            return "Target extra shares must be 0% or higher."
        }

        guard inputs.sellFeeTotal >= 0 else {
            return "Sell fees must be 0 or higher."
        }

        guard inputs.buyFeeTotal >= 0 else {
            return "Buy fees must be 0 or higher."
        }

        guard inputs.slippagePercent >= 0 else {
            return "Slippage must be 0% or higher."
        }

        return nil
    }
}

private enum BuybackFormat {
    static let locale = Locale(identifier: "en_US_POSIX")
}

extension String {
    var normalizedStockSymbol: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    var normalizedCurrencyCode: String {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter(\.isLetter)
        return normalized.count == 3 ? normalized : BuybackCalculator.defaultCurrencyCode
    }
}

extension Double {
    var eurString: String {
        moneyString(currencyCode: "EUR")
    }

    func moneyString(currencyCode: String) -> String {
        formatted(
            .currency(code: currencyCode.normalizedCurrencyCode)
                .precision(.fractionLength(2))
                .locale(BuybackFormat.locale)
        )
    }

    var percentString: String {
        formatted(
            .number
                .precision(.fractionLength(2))
                .locale(BuybackFormat.locale)
        ) + "%"
    }

    var compactPercentString: String {
        formatted(
            .number
                .precision(.fractionLength(0...1))
                .locale(BuybackFormat.locale)
        ) + "%"
    }

    var shareString: String {
        formatted(
            .number
                .precision(.fractionLength(0...3))
                .locale(BuybackFormat.locale)
        )
    }

    var inputString: String {
        formatted(
            .number
                .precision(.fractionLength(0...3))
                .locale(BuybackFormat.locale)
        )
    }

    fileprivate var keyString: String {
        String(format: "%.4f", locale: BuybackFormat.locale, self)
    }
}
