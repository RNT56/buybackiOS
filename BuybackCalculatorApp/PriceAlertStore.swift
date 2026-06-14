import Combine
import Foundation
import UserNotifications

@MainActor
final class PriceAlertStore: ObservableObject {
    @Published private(set) var alerts: [PriceAlert] = []
    @Published var statusMessage: LookupMessage?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) {
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
        statusMessage = .info("Alert armed at \(targetPrice.moneyString(currencyCode: currencyCode)). It is checked when app prices refresh.")
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

    @discardableResult
    func evaluate(symbol: String, price: Double, calculation: BuybackCalculation) -> Bool {
        guard let index = PriceAlertEvaluator.triggerIndex(
            in: alerts,
            symbol: symbol,
            price: price
        ) else {
            return false
        }

        alerts[index].lastTriggeredAt = .now
        persist()
        scheduleNotification(
            alert: alerts[index],
            currentPrice: price,
            buybackLimit: calculation.maximumBuybackPrice
        )
        statusMessage = .info("Alert triggered for \(alerts[index].symbol).")
        return true
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
        alerts = PriceAlertStorage.load(userDefaults: userDefaults)
    }

    private func persist() {
        PriceAlertStorage.save(alerts, userDefaults: userDefaults)
    }
}
