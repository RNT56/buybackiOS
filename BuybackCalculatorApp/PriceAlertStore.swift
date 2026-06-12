import Combine
import Foundation
import UserNotifications

struct PriceAlert: Codable, Equatable, Identifiable {
    var id: String { symbol }

    var symbol: String
    var targetPrice: Double
    var currencyCode: String
    var isEnabled: Bool
    var lastTriggeredAt: Date?
}

@MainActor
final class PriceAlertStore: ObservableObject {
    @Published private(set) var alerts: [PriceAlert] = []
    @Published var statusMessage: LookupMessage?

    private let storageKey = "buybackCalculator.priceAlerts"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func alert(for symbol: String) -> PriceAlert? {
        alerts.first { $0.symbol == symbol.normalizedStockSymbol }
    }

    func save(symbol: String, targetPrice: Double, currencyCode: String) {
        let normalizedSymbol = symbol.normalizedStockSymbol
        guard !normalizedSymbol.isEmpty, targetPrice.isFinite, targetPrice > 0 else {
            statusMessage = .warning("Set a valid symbol and alert price.")
            return
        }

        alerts.removeAll { $0.symbol == normalizedSymbol }
        alerts.insert(
            PriceAlert(
                symbol: normalizedSymbol,
                targetPrice: targetPrice,
                currencyCode: currencyCode.normalizedCurrencyCode,
                isEnabled: true,
                lastTriggeredAt: nil
            ),
            at: 0
        )
        persist()
        statusMessage = .info("Alert armed at \(targetPrice.moneyString(currencyCode: currencyCode)).")
    }

    func disable(symbol: String) {
        let normalizedSymbol = symbol.normalizedStockSymbol
        guard let index = alerts.firstIndex(where: { $0.symbol == normalizedSymbol }) else {
            return
        }

        alerts[index].isEnabled = false
        persist()
        statusMessage = .info("Alert disabled.")
    }

    func evaluate(symbol: String, price: Double, calculation: BuybackCalculation) {
        let normalizedSymbol = symbol.normalizedStockSymbol
        guard let index = alerts.firstIndex(where: { $0.symbol == normalizedSymbol }),
              alerts[index].isEnabled,
              price.isFinite,
              price > 0,
              price <= alerts[index].targetPrice,
              shouldTrigger(alerts[index])
        else {
            return
        }

        alerts[index].lastTriggeredAt = .now
        persist()
        scheduleNotification(
            alert: alerts[index],
            currentPrice: price,
            buybackLimit: calculation.maximumBuybackPrice
        )
        statusMessage = .info("Alert triggered for \(normalizedSymbol).")
    }

    private func shouldTrigger(_ alert: PriceAlert) -> Bool {
        guard let lastTriggeredAt = alert.lastTriggeredAt else {
            return true
        }

        return abs(lastTriggeredAt.timeIntervalSinceNow) > 60 * 60 * 6
    }

    private func scheduleNotification(alert: PriceAlert, currentPrice: Double, buybackLimit: Double) {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    await MainActor.run {
                        statusMessage = .warning("Notifications are disabled for price alerts.")
                    }
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = "\(alert.symbol) reached your buy-back alert"
                content.body = "Current price \(currentPrice.moneyString(currencyCode: alert.currencyCode)); limit \(buybackLimit.moneyString(currencyCode: alert.currencyCode))."
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "buyback-alert-\(alert.symbol)",
                    content: content,
                    trigger: nil
                )
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                await MainActor.run {
                    statusMessage = .warning("Could not schedule the alert notification.")
                }
            }
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data)
        else {
            alerts = []
            return
        }

        alerts = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alerts) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
