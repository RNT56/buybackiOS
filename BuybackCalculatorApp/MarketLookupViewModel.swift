import Combine
import Foundation

@MainActor
final class MarketLookupViewModel: ObservableObject {
    @Published var suggestions: [MarketAsset] = []
    @Published var selectedAsset: MarketAsset?
    @Published var quote: MarketQuote?
    @Published var message: LookupMessage?
    @Published var isSearching = false
    @Published var isFetchingQuote = false

    private var client = MarketDataClientFactory.make()
    private var searchCache: [String: CachedSearch] = [:]
    private var quoteCache: [String: CachedQuote] = [:]
    private var searchTask: Task<Void, Never>?
    private var quoteRequestID = UUID()

    func configure(finnhubAPIKey: String?, openFIGIAPIKey: String?) {
        client = MarketDataClientFactory.make(
            finnhubAPIKey: finnhubAPIKey,
            openFIGIAPIKey: openFIGIAPIKey
        )
        searchTask?.cancel()
        quoteRequestID = UUID()
        searchCache.removeAll(keepingCapacity: true)
        quoteCache.removeAll(keepingCapacity: true)
        isSearching = false
        isFetchingQuote = false
    }

    func scheduleSearch(query: String) {
        searchTask?.cancel()

        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = cleanedQuery.uppercased()
        guard cleanedQuery.count >= 2 else {
            suggestions = []
            message = nil
            isSearching = false
            return
        }

        guard cleanedQuery.normalizedStockSymbol != selectedAsset?.symbol else {
            suggestions = []
            isSearching = false
            return
        }

        if let cachedResults = searchCache[cacheKey], cachedResults.isFresh {
            suggestions = cachedResults.results
            isSearching = false
            message = cachedResults.results.isEmpty ? .info("No matching assets found.") : nil
            return
        }

        guard let client else {
            suggestions = []
            isSearching = false
            message = .warning("Add a Finnhub API key in Settings to enable autocomplete and live prices.")
            return
        }

        isSearching = true
        message = nil

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                let results = try await client.searchAssets(query: cleanedQuery)
                guard !Task.isCancelled else { return }
                self?.applySearchResults(results, cacheKey: cacheKey)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.applySearchError(error)
            }
        }
    }

    func prepareSelection(_ asset: MarketAsset) {
        selectedAsset = asset
        suggestions = []
        message = nil
        quote = nil
    }

    func restoreSelection(_ asset: MarketAsset) {
        selectedAsset = asset
    }

    func clearSelection() {
        selectedAsset = nil
        quote = nil
    }

    func fetchQuote(for asset: MarketAsset) async -> MarketQuote? {
        let requestID = UUID()
        quoteRequestID = requestID

        let cacheKey = asset.id
        if let cached = quoteCache[cacheKey], cached.isFresh {
            selectedAsset = asset
            quote = cached.quote
            message = quoteMessage(for: cached.quote)
            return cached.quote
        }

        guard let client else {
            quote = nil
            message = .warning("Live quote unavailable until a Finnhub API key is configured.")
            return nil
        }

        selectedAsset = asset
        isFetchingQuote = true
        message = nil

        do {
            let fetchedQuote = try await client.quote(for: asset)
            guard quoteRequestID == requestID, selectedAsset?.id == asset.id else {
                return nil
            }

            quote = fetchedQuote
            quoteCache[cacheKey] = CachedQuote(quote: fetchedQuote, storedAt: .now)
            isFetchingQuote = false
            message = quoteMessage(for: fetchedQuote)
            return fetchedQuote
        } catch {
            guard quoteRequestID == requestID, selectedAsset?.id == asset.id else {
                return nil
            }

            quote = nil
            isFetchingQuote = false
            message = .warning(message(for: error))
            return nil
        }
    }

    private func applySearchResults(_ results: [MarketAsset], cacheKey: String) {
        searchCache[cacheKey] = CachedSearch(results: results, storedAt: .now)
        trimSearchCache()
        suggestions = results
        isSearching = false
        message = results.isEmpty ? .info("No matching assets found.") : nil
    }

    private func applySearchError(_ error: Error) {
        suggestions = []
        isSearching = false
        message = .warning(message(for: error))
    }

    private func trimSearchCache() {
        let maximumEntries = 40
        guard searchCache.count > maximumEntries else { return }

        let keysToRemove = searchCache
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(searchCache.count - maximumEntries)
            .map(\.key)

        keysToRemove.forEach { searchCache.removeValue(forKey: $0) }
    }

    private func quoteMessage(for quote: MarketQuote) -> LookupMessage? {
        guard quote.isStale else { return nil }
        return .warning(quote.statusMessage ?? "Quote timestamp is stale; verify the price before trading.")
    }

    private func message(for error: Error) -> String {
        if let marketDataError = error as? MarketDataError {
            return marketDataError.localizedDescription
        }
        return "Market-data request failed. Enter the price manually."
    }

    private struct CachedSearch {
        let results: [MarketAsset]
        let storedAt: Date

        var isFresh: Bool {
            abs(storedAt.timeIntervalSinceNow) < 5 * 60
        }
    }

    private struct CachedQuote {
        let quote: MarketQuote
        let storedAt: Date

        var isFresh: Bool {
            abs(storedAt.timeIntervalSinceNow) < 60
        }
    }
}

struct LookupMessage: Equatable {
    enum Style {
        case info
        case warning
    }

    let text: String
    let style: Style

    static func info(_ text: String) -> LookupMessage {
        LookupMessage(text: text, style: .info)
    }

    static func warning(_ text: String) -> LookupMessage {
        LookupMessage(text: text, style: .warning)
    }
}
