import Foundation

struct CachedMarketQuote: Codable, Equatable, Sendable {
    let assetID: String
    let quote: MarketQuote
    let storedAt: Date
}

enum MarketQuoteRefreshStatus: Equatable, Sendable {
    case live
    case cached(nextRefreshAt: Date)
    case cachedFallback(reason: String)
    case unavailable(reason: String)
}

struct MarketQuoteRefreshResult: Equatable, Sendable {
    let quote: MarketQuote?
    let status: MarketQuoteRefreshStatus
}

enum MarketQuoteCache {
    static let storageKey = "buybackCalculator.marketQuoteCache"
    static let minimumRefreshInterval: TimeInterval = 5 * 60
    static let widgetTimelineInterval: TimeInterval = 15 * 60

    private static let maximumEntries = 40
    private static let retentionInterval: TimeInterval = 3 * 24 * 60 * 60

    static func cachedQuote(
        for asset: MarketAsset,
        now: Date = .now,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) -> CachedMarketQuote? {
        let key = cacheKey(for: asset)
        guard let cached = load(userDefaults: userDefaults)[key],
              now.timeIntervalSince(cached.storedAt) < retentionInterval
        else {
            return nil
        }

        return cached
    }

    static func cachedResult(
        for asset: MarketAsset,
        reason: String,
        now: Date = .now,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) -> MarketQuoteRefreshResult {
        if let cached = cachedQuote(for: asset, now: now, userDefaults: userDefaults) {
            return MarketQuoteRefreshResult(quote: cached.quote, status: .cachedFallback(reason: reason))
        }

        return MarketQuoteRefreshResult(quote: nil, status: .unavailable(reason: reason))
    }

    static func refreshQuote(
        for asset: MarketAsset,
        client: any MarketDataClient,
        now: Date = .now,
        minimumRefreshInterval: TimeInterval = Self.minimumRefreshInterval,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) async -> MarketQuoteRefreshResult {
        if let cached = cachedQuote(for: asset, now: now, userDefaults: userDefaults) {
            let nextRefreshAt = cached.storedAt.addingTimeInterval(minimumRefreshInterval)
            if now < nextRefreshAt {
                return MarketQuoteRefreshResult(quote: cached.quote, status: .cached(nextRefreshAt: nextRefreshAt))
            }
        }

        do {
            let quote = try await client.quote(for: asset)
            store(quote, for: asset, storedAt: now, userDefaults: userDefaults)
            return MarketQuoteRefreshResult(quote: quote, status: .live)
        } catch {
            let reason = message(for: error)
            if let cached = cachedQuote(for: asset, now: now, userDefaults: userDefaults) {
                return MarketQuoteRefreshResult(quote: cached.quote, status: .cachedFallback(reason: reason))
            }

            return MarketQuoteRefreshResult(quote: nil, status: .unavailable(reason: reason))
        }
    }

    static func store(
        _ quote: MarketQuote,
        for asset: MarketAsset,
        storedAt: Date = .now,
        userDefaults: UserDefaults = BuybackSharedStorage.userDefaults
    ) {
        let key = cacheKey(for: asset)
        var entries = load(userDefaults: userDefaults)
        entries[key] = CachedMarketQuote(assetID: key, quote: quote, storedAt: storedAt)
        save(trimmed(entries, now: storedAt), userDefaults: userDefaults)
    }

    static func clear(userDefaults: UserDefaults = BuybackSharedStorage.userDefaults) {
        userDefaults.removeObject(forKey: storageKey)
    }

    static func cacheKey(for asset: MarketAsset) -> String {
        asset.id
    }

    private static func load(userDefaults: UserDefaults) -> [String: CachedMarketQuote] {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: CachedMarketQuote].self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private static func save(_ entries: [String: CachedMarketQuote], userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    private static func trimmed(_ entries: [String: CachedMarketQuote], now: Date) -> [String: CachedMarketQuote] {
        let retained = entries.filter { now.timeIntervalSince($0.value.storedAt) < retentionInterval }
        guard retained.count > maximumEntries else {
            return retained
        }

        return Dictionary(
            uniqueKeysWithValues: retained
                .sorted { $0.value.storedAt > $1.value.storedAt }
                .prefix(maximumEntries)
                .map { ($0.key, $0.value) }
        )
    }

    private static func message(for error: Error) -> String {
        if let marketDataError = error as? MarketDataError {
            return marketDataError.localizedDescription
        }

        return "Market-data request failed."
    }
}
