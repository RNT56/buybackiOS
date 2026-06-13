import Combine
import Foundation

enum BuybackSharedStorage {
    static let appGroupIdentifier = "group.com.schtack.BuybackCalculator"

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

enum SavedScenarioStorage {
    static let storageKey = "buybackCalculator.savedScenarios"

    static func load(userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) -> [SavedBuybackScenario] {
        if let scenarios = decode(from: userDefaults) {
            return scenarios.sorted { $0.savedAt > $1.savedAt }
        }

        if userDefaults !== UserDefaults.standard,
           let legacyScenarios = decode(from: .standard) {
            save(legacyScenarios, userDefaults: userDefaults)
            return legacyScenarios.sorted { $0.savedAt > $1.savedAt }
        }

        return []
    }

    static func save(_ scenarios: [SavedBuybackScenario], userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) {
        guard let data = try? JSONEncoder().encode(scenarios) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    @discardableResult
    static func freezeScenario(
        id: UUID,
        sellPrice: Double,
        currencyCode: String,
        quoteTimestamp: Date?,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) -> Bool {
        guard sellPrice.isFinite, sellPrice > 0 else {
            return false
        }

        var scenarios = load(userDefaults: userDefaults)
        guard let index = scenarios.firstIndex(where: { $0.id == id }) else {
            return false
        }

        scenarios[index].trackingState = .frozen
        scenarios[index].frozenSellPrice = sellPrice
        scenarios[index].frozenCurrencyCode = currencyCode.normalizedCurrencyCode
        scenarios[index].frozenAt = .now
        scenarios[index].frozenQuoteTimestamp = quoteTimestamp
        save(scenarios, userDefaults: userDefaults)
        return true
    }

    @discardableResult
    static func unfreezeScenario(
        id: UUID,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) -> Bool {
        var scenarios = load(userDefaults: userDefaults)
        guard let index = scenarios.firstIndex(where: { $0.id == id }) else {
            return false
        }

        scenarios[index].trackingState = .watching
        scenarios[index].frozenSellPrice = nil
        scenarios[index].frozenCurrencyCode = nil
        scenarios[index].frozenAt = nil
        scenarios[index].frozenQuoteTimestamp = nil
        save(scenarios, userDefaults: userDefaults)
        return true
    }

    private static func decode(from userDefaults: UserDefaults) -> [SavedBuybackScenario]? {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedBuybackScenario].self, from: data)
        else {
            return nil
        }

        return decoded
    }
}

enum ScenarioTrackingState: String, Codable, CaseIterable, Identifiable, Sendable {
    case watching
    case frozen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watching:
            return "Watching"
        case .frozen:
            return "Frozen"
        }
    }
}

struct SavedBuybackScenario: Codable, Equatable, Identifiable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case savedAt
        case assetQuery
        case selectedAsset
        case manualPriceEnabled
        case symbol
        case currencyCode
        case sellPrice
        case gainPercent
        case sharesToSell
        case averageCostBasis
        case taxProfile
        case taxRatePercent
        case taxCurrencyCode
        case fxRateToTaxCurrency
        case targetExtraSharesPercent
        case sellFeeTotal
        case buyFeeTotal
        case slippagePercent
        case taxLotsEnabled
        case taxLots
        case trackingState
        case frozenSellPrice
        case frozenCurrencyCode
        case frozenAt
        case frozenQuoteTimestamp
    }

    var id: UUID
    var name: String
    var savedAt: Date
    var assetQuery: String
    var selectedAsset: MarketAsset?
    var manualPriceEnabled: Bool
    var symbol: String
    var currencyCode: String
    var sellPrice: Double
    var gainPercent: Double
    var sharesToSell: Double
    var averageCostBasis: Double?
    var taxProfile: TaxProfile
    var taxRatePercent: Double
    var taxCurrencyCode: String
    var fxRateToTaxCurrency: Double
    var targetExtraSharesPercent: Double
    var sellFeeTotal: Double
    var buyFeeTotal: Double
    var slippagePercent: Double
    var taxLotsEnabled: Bool
    var taxLots: [TaxLot]
    var trackingState: ScenarioTrackingState
    var frozenSellPrice: Double?
    var frozenCurrencyCode: String?
    var frozenAt: Date?
    var frozenQuoteTimestamp: Date?

    init(
        id: UUID,
        name: String,
        savedAt: Date,
        assetQuery: String,
        selectedAsset: MarketAsset?,
        manualPriceEnabled: Bool,
        symbol: String,
        currencyCode: String,
        sellPrice: Double,
        gainPercent: Double,
        sharesToSell: Double,
        averageCostBasis: Double? = nil,
        taxProfile: TaxProfile = BuybackCalculator.defaultTaxProfile,
        taxRatePercent: Double,
        taxCurrencyCode: String = BuybackCalculator.defaultCurrencyCode,
        fxRateToTaxCurrency: Double = BuybackCalculator.defaultFXRateToTaxCurrency,
        targetExtraSharesPercent: Double,
        sellFeeTotal: Double,
        buyFeeTotal: Double,
        slippagePercent: Double,
        taxLotsEnabled: Bool = false,
        taxLots: [TaxLot] = [],
        trackingState: ScenarioTrackingState = .watching,
        frozenSellPrice: Double? = nil,
        frozenCurrencyCode: String? = nil,
        frozenAt: Date? = nil,
        frozenQuoteTimestamp: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        self.assetQuery = assetQuery
        self.selectedAsset = selectedAsset
        self.manualPriceEnabled = manualPriceEnabled
        self.symbol = symbol
        self.currencyCode = currencyCode
        self.sellPrice = sellPrice
        self.gainPercent = gainPercent
        self.sharesToSell = sharesToSell
        self.averageCostBasis = averageCostBasis ?? Self.legacyAverageCostBasis(sellPrice: sellPrice, gainPercent: gainPercent)
        self.taxProfile = taxProfile
        self.taxRatePercent = taxRatePercent
        self.taxCurrencyCode = taxCurrencyCode
        self.fxRateToTaxCurrency = fxRateToTaxCurrency
        self.targetExtraSharesPercent = targetExtraSharesPercent
        self.sellFeeTotal = sellFeeTotal
        self.buyFeeTotal = buyFeeTotal
        self.slippagePercent = slippagePercent
        self.taxLotsEnabled = taxLotsEnabled
        self.taxLots = taxLots
        self.trackingState = trackingState
        self.frozenSellPrice = frozenSellPrice
        self.frozenCurrencyCode = frozenCurrencyCode?.normalizedCurrencyCode
        self.frozenAt = frozenAt
        self.frozenQuoteTimestamp = frozenQuoteTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        assetQuery = try container.decode(String.self, forKey: .assetQuery)
        selectedAsset = try container.decodeIfPresent(MarketAsset.self, forKey: .selectedAsset)
        manualPriceEnabled = try container.decode(Bool.self, forKey: .manualPriceEnabled)
        symbol = try container.decode(String.self, forKey: .symbol)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        sellPrice = try container.decode(Double.self, forKey: .sellPrice)
        gainPercent = try container.decode(Double.self, forKey: .gainPercent)
        sharesToSell = try container.decode(Double.self, forKey: .sharesToSell)
        averageCostBasis = try container.decodeIfPresent(Double.self, forKey: .averageCostBasis)
            ?? Self.legacyAverageCostBasis(sellPrice: sellPrice, gainPercent: gainPercent)
        taxProfile = try container.decodeIfPresent(TaxProfile.self, forKey: .taxProfile) ?? BuybackCalculator.defaultTaxProfile
        taxRatePercent = try container.decode(Double.self, forKey: .taxRatePercent)
        taxCurrencyCode = try container.decodeIfPresent(String.self, forKey: .taxCurrencyCode) ?? currencyCode
        fxRateToTaxCurrency = try container.decodeIfPresent(Double.self, forKey: .fxRateToTaxCurrency) ?? BuybackCalculator.defaultFXRateToTaxCurrency
        targetExtraSharesPercent = try container.decode(Double.self, forKey: .targetExtraSharesPercent)
        sellFeeTotal = try container.decode(Double.self, forKey: .sellFeeTotal)
        buyFeeTotal = try container.decode(Double.self, forKey: .buyFeeTotal)
        slippagePercent = try container.decode(Double.self, forKey: .slippagePercent)
        taxLotsEnabled = try container.decodeIfPresent(Bool.self, forKey: .taxLotsEnabled) ?? false
        taxLots = try container.decodeIfPresent([TaxLot].self, forKey: .taxLots) ?? []
        trackingState = try container.decodeIfPresent(ScenarioTrackingState.self, forKey: .trackingState) ?? .watching
        frozenSellPrice = try container.decodeIfPresent(Double.self, forKey: .frozenSellPrice)
        frozenCurrencyCode = try container.decodeIfPresent(String.self, forKey: .frozenCurrencyCode)?.normalizedCurrencyCode
        frozenAt = try container.decodeIfPresent(Date.self, forKey: .frozenAt)
        frozenQuoteTimestamp = try container.decodeIfPresent(Date.self, forKey: .frozenQuoteTimestamp)
    }

    var displayTitle: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displaySymbol : name
    }

    var displaySymbol: String {
        symbol.normalizedStockSymbol.isEmpty ? BuybackCalculator.defaultSymbol : symbol.normalizedStockSymbol
    }

    var calculation: BuybackCalculation? {
        calculation(using: nil)
    }

    private static func legacyAverageCostBasis(sellPrice: Double, gainPercent: Double) -> Double? {
        guard sellPrice.isFinite,
              gainPercent.isFinite,
              sellPrice > 0,
              gainPercent > -100
        else {
            return nil
        }

        let basis = sellPrice / (1 + gainPercent / 100)
        return basis.isFinite && basis > 0 ? basis : nil
    }
}

@MainActor
final class SavedScenarioStore: ObservableObject {
    @Published private(set) var scenarios: [SavedBuybackScenario] = []

    private let userDefaults: UserDefaults
    private let maximumScenarios = 20

    init(userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) {
        self.userDefaults = userDefaults
        load()
    }

    func save(_ scenario: SavedBuybackScenario) {
        scenarios.removeAll { $0.id == scenario.id }
        scenarios.insert(scenario, at: 0)
        scenarios = Array(scenarios.prefix(maximumScenarios))
        persist()
    }

    func delete(_ scenario: SavedBuybackScenario) {
        scenarios.removeAll { $0.id == scenario.id }
        persist()
    }

    func reload() {
        load()
    }

    private func load() {
        scenarios = SavedScenarioStorage.load(userDefaults: userDefaults)
    }

    private func persist() {
        SavedScenarioStorage.save(scenarios, userDefaults: userDefaults)
    }
}
