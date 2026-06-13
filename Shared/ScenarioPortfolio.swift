import Foundation

extension SavedBuybackScenario {
    var isFrozen: Bool {
        trackingState == .frozen && validFrozenSellPrice != nil
    }

    var portfolioAsset: MarketAsset {
        if let selectedAsset {
            return selectedAsset
        }

        return MarketAsset(
            symbol: displaySymbol,
            name: displayTitle,
            currencyCode: currencyCode,
            source: .finnhub
        )
    }

    func activeSellPrice(using quote: MarketQuote?) -> Double? {
        if let validFrozenSellPrice {
            return validFrozenSellPrice
        }

        let quotePrice = quote?.price
        if let quotePrice, quotePrice.isFinite, quotePrice > 0 {
            return quotePrice
        }

        return sellPrice.isFinite && sellPrice > 0 ? sellPrice : nil
    }

    func currentMarketPrice(using quote: MarketQuote?) -> Double? {
        guard let price = quote?.price,
              price.isFinite,
              price > 0
        else {
            return nil
        }

        return price
    }

    func activeCurrencyCode(using quote: MarketQuote?) -> String {
        if isFrozen, let frozenCurrencyCode {
            return frozenCurrencyCode.normalizedCurrencyCode
        }

        return quote?.currencyCode ?? currencyCode
    }

    func calculation(using quote: MarketQuote?) -> BuybackCalculation? {
        guard let currentPrice = activeSellPrice(using: quote) else {
            return nil
        }
        let currentCurrencyCode = activeCurrencyCode(using: quote)

        if taxLotsEnabled,
           let lotAverageCostBasis = TaxLot.weightedAverageCostBasis(taxLots) {
            let lotShares = TaxLot.totalShares(taxLots)
            guard lotShares > 0 else { return nil }

            return BuybackCalculator.calculate(
                symbol: displaySymbol,
                sharesToSell: lotShares,
                averageCostBasis: lotAverageCostBasis,
                sellPrice: currentPrice,
                taxProfile: taxProfile,
                taxRatePercent: taxRatePercent,
                taxCurrencyCode: taxCurrencyCode,
                fxRateToTaxCurrency: fxRateToTaxCurrency,
                targetExtraSharesPercent: targetExtraSharesPercent,
                sellFeeTotal: sellFeeTotal,
                buyFeeTotal: buyFeeTotal,
                slippagePercent: slippagePercent,
                currencyCode: currentCurrencyCode
            )
        }

        if let averageCostBasis = resolvedAverageCostBasis {
            return BuybackCalculator.calculate(
                symbol: displaySymbol,
                sharesToSell: sharesToSell,
                averageCostBasis: averageCostBasis,
                sellPrice: currentPrice,
                taxProfile: taxProfile,
                taxRatePercent: taxRatePercent,
                taxCurrencyCode: taxCurrencyCode,
                fxRateToTaxCurrency: fxRateToTaxCurrency,
                targetExtraSharesPercent: targetExtraSharesPercent,
                sellFeeTotal: sellFeeTotal,
                buyFeeTotal: buyFeeTotal,
                slippagePercent: slippagePercent,
                currencyCode: currentCurrencyCode
            )
        }

        return BuybackCalculator.calculate(
            symbol: displaySymbol,
            sellPrice: currentPrice,
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
            currencyCode: currentCurrencyCode
        )
    }

    func isBuybackReady(using quote: MarketQuote?) -> Bool {
        guard isFrozen,
              let currentMarketPrice = currentMarketPrice(using: quote),
              let calculation = calculation(using: quote)
        else {
            return false
        }

        return currentMarketPrice <= calculation.maximumBuybackPrice
    }

    private var resolvedAverageCostBasis: Double? {
        guard let averageCostBasis,
              averageCostBasis.isFinite,
              averageCostBasis > 0
        else {
            return nil
        }

        return averageCostBasis
    }

    private var validFrozenSellPrice: Double? {
        guard trackingState == .frozen,
              let frozenSellPrice,
              frozenSellPrice.isFinite,
              frozenSellPrice > 0
        else {
            return nil
        }

        return frozenSellPrice
    }
}
