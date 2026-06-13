import Foundation

enum TaxProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case germany
    case usLongTerm
    case usShortTerm
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .germany:
            return "Germany"
        case .usLongTerm:
            return "US long"
        case .usShortTerm:
            return "US short"
        case .custom:
            return "Custom"
        }
    }

    var defaultTaxRatePercent: Double {
        switch self {
        case .germany:
            return BuybackCalculator.fixedTaxRatePercent
        case .usLongTerm:
            return 15
        case .usShortTerm:
            return 24
        case .custom:
            return BuybackCalculator.fixedTaxRatePercent
        }
    }

    var assumptionSummary: String {
        switch self {
        case .germany:
            return "Uses a flat 27% German capital-gains estimate."
        case .usLongTerm:
            return "Uses a simple 15% US long-term capital-gains estimate."
        case .usShortTerm:
            return "Uses a simple 24% US short-term ordinary-income estimate."
        case .custom:
            return "Uses the custom tax rate you enter."
        }
    }

    var assumptionDetails: String {
        switch self {
        case .germany:
            return "This is a planning estimate and does not model allowances, church tax, loss offsets, broker withholding, or tax-year-specific rules."
        case .usLongTerm:
            return "This does not model income brackets, state or local taxes, net investment income tax, wash-sale rules, or loss offsets."
        case .usShortTerm:
            return "This does not model actual marginal brackets, state or local taxes, net investment income tax, wash-sale rules, or loss offsets."
        case .custom:
            return "Use this when your actual tax situation differs from the built-in estimates. The calculator applies the entered rate to taxable gains only."
        }
    }

    func resolvedTaxRatePercent(customRatePercent: Double) -> Double {
        self == .custom ? customRatePercent : defaultTaxRatePercent
    }
}

struct TaxLot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var shares: Double
    var averageCostBasis: Double

    init(
        id: UUID = UUID(),
        shares: Double,
        averageCostBasis: Double
    ) {
        self.id = id
        self.shares = shares
        self.averageCostBasis = averageCostBasis
    }

    var isValid: Bool {
        shares.isFinite && averageCostBasis.isFinite && shares > 0 && averageCostBasis > 0
    }

    static func weightedAverageCostBasis(_ lots: [TaxLot]) -> Double? {
        let validLots = lots.filter(\.isValid)
        let shareCount = validLots.reduce(0) { $0 + $1.shares }
        guard shareCount > 0 else { return nil }

        let costBasisTotal = validLots.reduce(0) { partial, lot in
            partial + lot.shares * lot.averageCostBasis
        }

        return costBasisTotal / shareCount
    }

    static func totalShares(_ lots: [TaxLot]) -> Double {
        lots.filter(\.isValid).reduce(0) { $0 + $1.shares }
    }
}

struct BuybackInputs: Codable, Equatable, Sendable {
    var symbol: String
    var sharesToSell: Double
    var averageCostBasis: Double
    var sellPrice: Double
    var taxProfile: TaxProfile
    var taxRatePercent: Double
    var taxCurrencyCode: String
    var fxRateToTaxCurrency: Double
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
        taxProfile: TaxProfile = BuybackCalculator.defaultTaxProfile,
        taxRatePercent: Double = BuybackCalculator.fixedTaxRatePercent,
        taxCurrencyCode: String = BuybackCalculator.defaultCurrencyCode,
        fxRateToTaxCurrency: Double = BuybackCalculator.defaultFXRateToTaxCurrency,
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
        self.taxProfile = taxProfile
        self.taxRatePercent = taxRatePercent
        self.taxCurrencyCode = taxCurrencyCode.normalizedCurrencyCode
        self.fxRateToTaxCurrency = fxRateToTaxCurrency
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
            taxProfile.rawValue,
            taxRatePercent.keyString,
            taxCurrencyCode,
            fxRateToTaxCurrency.keyString,
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
    let taxProfile: TaxProfile
    let taxRatePercent: Double
    let taxCurrencyCode: String
    let fxRateToTaxCurrency: Double
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
    let taxableGainInTaxCurrency: Double
    let taxAmount: Double
    let taxAmountInTaxCurrency: Double
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
    static let defaultTaxProfile = TaxProfile.germany
    static let fixedTaxRatePercent: Double = 27
    static let fixedTargetExtraSharesPercent: Double = 2.5
    static let defaultSellFeeTotal: Double = 0
    static let defaultBuyFeeTotal: Double = 0
    static let defaultSlippagePercent: Double = 0
    static let defaultFXRateToTaxCurrency: Double = 1

    static var defaultInputs: BuybackInputs {
        BuybackInputs()
    }

    static func calculate(inputs: BuybackInputs) -> BuybackCalculation? {
        calculate(
            symbol: inputs.symbol,
            sharesToSell: inputs.sharesToSell,
            averageCostBasis: inputs.averageCostBasis,
            sellPrice: inputs.sellPrice,
            taxProfile: inputs.taxProfile,
            taxRatePercent: inputs.taxRatePercent,
            taxCurrencyCode: inputs.taxCurrencyCode,
            fxRateToTaxCurrency: inputs.fxRateToTaxCurrency,
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
        taxProfile: TaxProfile = defaultTaxProfile,
        taxRatePercent: Double = fixedTaxRatePercent,
        taxCurrencyCode: String = defaultCurrencyCode,
        fxRateToTaxCurrency: Double = defaultFXRateToTaxCurrency,
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
              fxRateToTaxCurrency.isFinite,
              targetExtraSharesPercent.isFinite,
              sellFeeTotal.isFinite,
              buyFeeTotal.isFinite,
              slippagePercent.isFinite,
              sharesToSell > 0,
              averageCostBasis > 0,
              sellPrice > 0,
              fxRateToTaxCurrency > 0,
              targetExtraSharesPercent >= 0,
              sellFeeTotal >= 0,
              buyFeeTotal >= 0,
              slippagePercent >= 0
        else {
            return nil
        }

        let normalizedSymbol = symbol.normalizedStockSymbol
        let normalizedCurrencyCode = currencyCode.normalizedCurrencyCode
        let normalizedTaxCurrencyCode = taxCurrencyCode.normalizedCurrencyCode
        let resolvedTaxRatePercent = taxProfile.resolvedTaxRatePercent(customRatePercent: taxRatePercent)
        guard resolvedTaxRatePercent.isFinite,
              resolvedTaxRatePercent >= 0,
              resolvedTaxRatePercent <= 100
        else {
            return nil
        }

        let gainAtSellPercent = ((sellPrice - averageCostBasis) / averageCostBasis) * 100
        let costBasisTotal = averageCostBasis * sharesToSell
        let grossProceeds = sellPrice * sharesToSell
        let netSaleProceeds = grossProceeds - sellFeeTotal
        let taxableGainTotal = max(0, netSaleProceeds - costBasisTotal)
        let taxableGainPerShare = taxableGainTotal / sharesToSell
        let taxableGainInTaxCurrency = taxableGainTotal * fxRateToTaxCurrency
        let taxAmountInTaxCurrency = taxableGainInTaxCurrency * resolvedTaxRatePercent / 100
        let taxAmount = taxAmountInTaxCurrency / fxRateToTaxCurrency
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
            taxProfile: taxProfile,
            taxRatePercent: resolvedTaxRatePercent,
            taxCurrencyCode: normalizedTaxCurrencyCode,
            fxRateToTaxCurrency: fxRateToTaxCurrency,
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
            taxableGainInTaxCurrency: taxableGainInTaxCurrency,
            taxAmount: taxAmount,
            taxAmountInTaxCurrency: taxAmountInTaxCurrency,
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
        taxProfile: TaxProfile = defaultTaxProfile,
        taxRatePercent: Double = fixedTaxRatePercent,
        taxCurrencyCode: String = defaultCurrencyCode,
        fxRateToTaxCurrency: Double = defaultFXRateToTaxCurrency,
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
            taxProfile: taxProfile,
            taxRatePercent: taxRatePercent,
            taxCurrencyCode: taxCurrencyCode,
            fxRateToTaxCurrency: fxRateToTaxCurrency,
            targetExtraSharesPercent: targetExtraSharesPercent,
            sellFeeTotal: sellFeeTotal,
            buyFeeTotal: buyFeeTotal,
            slippagePercent: slippagePercent,
            currencyCode: currencyCode
        )
    }

    static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        guard !trimmed.isEmpty else { return nil }

        for locale in [Locale.current, BuybackFormat.locale, Locale(identifier: "de_DE")] {
            if let value = decimalFormatter(locale: locale).number(from: trimmed)?.doubleValue,
               value.isFinite {
                return value
            }

            if let value = currencyFormatter(locale: locale).number(from: trimmed)?.doubleValue,
               value.isFinite {
                return value
            }
        }

        let filtered = trimmed
            .unicodeScalars
            .compactMap { scalar -> Character? in
                switch scalar {
                case "0"..."9", ".", ",", "-", "+":
                    return Character(scalar)
                default:
                    return nil
                }
            }

        guard filtered.contains(where: { $0.isNumber }) else { return nil }

        var sign = ""
        var body = String(filtered)
        if body.contains("-") {
            sign = "-"
        } else if body.contains("+") {
            sign = "+"
        }
        body.removeAll { $0 == "-" || $0 == "+" }

        let separatorIndices = body.indices.filter { body[$0] == "." || body[$0] == "," }
        let decimalSeparatorIndex: String.Index?
        if let lastDot = body.lastIndex(of: "."),
           let lastComma = body.lastIndex(of: ",") {
            decimalSeparatorIndex = lastDot > lastComma ? lastDot : lastComma
        } else if separatorIndices.count == 1,
                  let onlySeparator = separatorIndices.first {
            let digitsBefore = body[..<onlySeparator].filter(\.isNumber).count
            let digitsAfter = body[body.index(after: onlySeparator)...].filter(\.isNumber).count
            let localeDecimalSeparator = Locale.current.decimalSeparator ?? "."
            let separator = String(body[onlySeparator])
            if digitsAfter == 0 {
                decimalSeparatorIndex = nil
            } else if digitsAfter == 3, digitsBefore <= 3, separator != localeDecimalSeparator {
                decimalSeparatorIndex = nil
            } else {
                decimalSeparatorIndex = onlySeparator
            }
        } else {
            decimalSeparatorIndex = nil
        }

        var normalized = sign
        for index in body.indices {
            let character = body[index]
            if character.isNumber {
                normalized.append(character)
            } else if index == decimalSeparatorIndex {
                normalized.append(".")
            }
        }

        guard normalized != "-", normalized != "+", normalized != ".", !normalized.isEmpty else {
            return nil
        }

        return Double(normalized).flatMap { $0.isFinite ? $0 : nil }
    }

    private static func decimalFormatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = true
        return formatter
    }

    private static func currencyFormatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.isLenient = true
        return formatter
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

        let resolvedTaxRatePercent = inputs.taxProfile.resolvedTaxRatePercent(customRatePercent: inputs.taxRatePercent)
        guard resolvedTaxRatePercent >= 0, resolvedTaxRatePercent <= 100 else {
            return "Tax rate must be between 0% and 100%."
        }

        guard inputs.fxRateToTaxCurrency > 0 else {
            return "FX rate must be greater than 0."
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
