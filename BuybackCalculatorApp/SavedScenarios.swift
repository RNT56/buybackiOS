import Combine
import Foundation

struct SavedBuybackScenario: Codable, Equatable, Identifiable {
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
    var taxRatePercent: Double
    var targetExtraSharesPercent: Double
    var sellFeeTotal: Double
    var buyFeeTotal: Double
    var slippagePercent: Double

    var displayTitle: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displaySymbol : name
    }

    var displaySymbol: String {
        symbol.normalizedStockSymbol.isEmpty ? BuybackCalculator.defaultSymbol : symbol.normalizedStockSymbol
    }

    var calculation: BuybackCalculation? {
        BuybackCalculator.calculate(
            symbol: symbol,
            sellPrice: sellPrice,
            gainAtSellPercent: gainPercent,
            sharesToSell: sharesToSell,
            taxRatePercent: taxRatePercent,
            targetExtraSharesPercent: targetExtraSharesPercent,
            sellFeeTotal: sellFeeTotal,
            buyFeeTotal: buyFeeTotal,
            slippagePercent: slippagePercent,
            currencyCode: currencyCode
        )
    }
}

@MainActor
final class SavedScenarioStore: ObservableObject {
    @Published private(set) var scenarios: [SavedBuybackScenario] = []

    private let userDefaults: UserDefaults
    private let storageKey = "buybackCalculator.savedScenarios"
    private let maximumScenarios = 20

    init(userDefaults: UserDefaults = .standard) {
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

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedBuybackScenario].self, from: data)
        else {
            scenarios = []
            return
        }

        scenarios = decoded.sorted { $0.savedAt > $1.savedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scenarios) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
