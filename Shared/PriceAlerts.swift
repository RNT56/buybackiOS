import Foundation

struct PriceAlert: Codable, Equatable, Identifiable, Sendable {
    var id: String { symbol }

    var symbol: String
    var targetPrice: Double
    var currencyCode: String
    var isEnabled: Bool
    var lastTriggeredAt: Date?
}

enum PriceAlertStorage {
    static let storageKey = "buybackCalculator.priceAlerts"

    static func load(
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults,
        legacyUserDefaults: UserDefaults? = .standard
    ) -> [PriceAlert] {
        if let alerts = decode(from: userDefaults) {
            return alerts
        }

        guard let legacyUserDefaults,
              legacyUserDefaults !== userDefaults,
              let legacyAlerts = decode(from: legacyUserDefaults)
        else {
            return []
        }

        save(legacyAlerts, userDefaults: userDefaults)
        return legacyAlerts
    }

    static func save(_ alerts: [PriceAlert], userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) {
        guard let data = try? JSONEncoder().encode(alerts) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    private static func decode(from userDefaults: UserDefaults) -> [PriceAlert]? {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data)
        else {
            return nil
        }

        return decoded
    }
}

enum PriceAlertEvaluator {
    static let triggerThrottle: TimeInterval = 60 * 60 * 6

    static func triggerIndex(
        in alerts: [PriceAlert],
        symbol: String,
        price: Double,
        now: Date = .now
    ) -> Int? {
        let normalizedSymbol = symbol.normalizedStockSymbol
        guard price.isFinite, price > 0 else { return nil }

        return alerts.firstIndex { alert in
            alert.symbol == normalizedSymbol && shouldTrigger(alert, price: price, now: now)
        }
    }

    static func shouldTrigger(_ alert: PriceAlert, price: Double, now: Date = .now) -> Bool {
        guard alert.isEnabled,
              price.isFinite,
              alert.targetPrice.isFinite,
              price > 0,
              alert.targetPrice > 0,
              price <= alert.targetPrice
        else {
            return false
        }

        guard let lastTriggeredAt = alert.lastTriggeredAt else {
            return true
        }

        return now.timeIntervalSince(lastTriggeredAt) > triggerThrottle
    }
}
