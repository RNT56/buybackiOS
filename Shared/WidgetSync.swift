import Foundation

enum BuybackWidgetKind {
    static let value = "BuybackWidget"
    static let portfolio = "BuybackPortfolioWidget"
}

struct WidgetSyncSnapshot: Codable, Equatable, Sendable {
    let revision: Int
    let updatedAt: Date
    let reason: String

    static let initial = WidgetSyncSnapshot(revision: 0, updatedAt: .distantPast, reason: "initial")
    static let preview = WidgetSyncSnapshot(revision: 1, updatedAt: .now, reason: "preview")
}

enum WidgetSyncStorage {
    static let storageKey = "buybackCalculator.widgetSync"

    @discardableResult
    static func bump(
        reason: String,
        now: Date = .now,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) -> WidgetSyncSnapshot {
        let current = load(userDefaults: userDefaults)
        let next = WidgetSyncSnapshot(
            revision: current.revision + 1,
            updatedAt: now,
            reason: reason
        )
        save(next, userDefaults: userDefaults)
        return next
    }

    static func load(userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) -> WidgetSyncSnapshot {
        guard let data = userDefaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetSyncSnapshot.self, from: data)
        else {
            return .initial
        }

        return snapshot
    }

    private static func save(_ snapshot: WidgetSyncSnapshot, userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
