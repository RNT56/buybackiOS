import Foundation

enum MarketDataSource: String, Codable, Sendable {
    case finnhub = "Finnhub"
    case openFIGI = "OpenFIGI"
}

struct MarketAsset: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String {
        [
            source.rawValue,
            symbol.normalizedStockSymbol,
            exchange.uppercased(),
            currencyCode.normalizedCurrencyCode,
            figi ?? "",
            isin ?? "",
            wkn ?? ""
        ].joined(separator: "|")
    }

    let symbol: String
    let name: String
    let exchange: String
    let currencyCode: String
    let isin: String?
    let wkn: String?
    let figi: String?
    let source: MarketDataSource

    init(
        symbol: String,
        name: String,
        exchange: String = "",
        currencyCode: String = BuybackCalculator.defaultCurrencyCode,
        isin: String? = nil,
        wkn: String? = nil,
        figi: String? = nil,
        source: MarketDataSource
    ) {
        self.symbol = symbol.normalizedStockSymbol
        self.name = name.trimmedForDisplay
        self.exchange = exchange.trimmedForDisplay
        self.currencyCode = currencyCode.normalizedCurrencyCode
        self.isin = isin?.trimmedForDisplay.nilIfEmpty
        self.wkn = wkn?.trimmedForDisplay.nilIfEmpty
        self.figi = figi?.trimmedForDisplay.nilIfEmpty
        self.source = source
    }
}

struct MarketQuote: Codable, Equatable, Sendable {
    let symbol: String
    let price: Double
    let currencyCode: String
    let timestamp: Date?
    let source: MarketDataSource
    let isStale: Bool
    let statusMessage: String?
}

enum MarketDataError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case invalidURL
    case rateLimited
    case noResults
    case quoteUnavailable
    case badStatusCode(Int)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Finnhub API key to enable live search and quotes."
        case .invalidURL:
            return "The market-data request could not be built."
        case .rateLimited:
            return "The market-data API limit was reached. Try again later or use a manual price."
        case .noResults:
            return "No matching assets were found."
        case .quoteUnavailable:
            return "A live quote is not available for this asset. Enter a manual price."
        case .badStatusCode(let statusCode):
            return "The market-data service returned HTTP \(statusCode)."
        case .invalidResponse(let message):
            return message
        }
    }
}

protocol MarketDataClient: Sendable {
    func searchAssets(query: String) async throws -> [MarketAsset]
    func quote(for asset: MarketAsset) async throws -> MarketQuote
}

enum MarketDataURLSessionFactory {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 14
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = URLCache(memoryCapacity: 1_500_000, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()
}

struct CompositeMarketDataClient: MarketDataClient {
    let finnhub: FinnhubMarketDataClient
    let openFIGI: OpenFIGIIdentifierResolver

    func searchAssets(query: String) async throws -> [MarketAsset] {
        let cleanedQuery = query.trimmedForDisplay
        guard cleanedQuery.count >= 2 else { return [] }

        var providerErrors: [Error] = []

        if cleanedQuery.isLikelyWKN {
            do {
                let mapped = try await openFIGI.resolveIdentifier(cleanedQuery, idType: .wkn)
                let mappedMatches = try await enrichMappedAssets(mapped, originalQuery: cleanedQuery)
                if !mappedMatches.isEmpty {
                    return mappedMatches
                }
            } catch {
                providerErrors.append(error)
            }
        }

        do {
            let directMatches = try await finnhub.searchAssets(query: cleanedQuery)
            if !directMatches.isEmpty {
                return directMatches
            }
        } catch {
            providerErrors.append(error)
        }

        if cleanedQuery.isLikelyISIN {
            do {
                let mapped = try await openFIGI.resolveIdentifier(cleanedQuery, idType: .isin)
                let mappedMatches = try await enrichMappedAssets(mapped, originalQuery: cleanedQuery)
                if !mappedMatches.isEmpty {
                    return mappedMatches
                }
            } catch {
                providerErrors.append(error)
            }
        }

        if let actionableError = providerErrors.actionableMarketDataError {
            throw actionableError
        }

        throw MarketDataError.noResults
    }

    func quote(for asset: MarketAsset) async throws -> MarketQuote {
        try await finnhub.quote(for: asset)
    }

    private func enrichMappedAssets(
        _ mappedAssets: [MarketAsset],
        originalQuery: String
    ) async throws -> [MarketAsset] {
        var merged: [MarketAsset] = []

        for mappedAsset in mappedAssets.prefix(4) {
            let searchTerm = mappedAsset.symbol.isEmpty ? mappedAsset.name : mappedAsset.symbol
            let finnhubMatches = (try? await finnhub.searchAssets(query: searchTerm)) ?? []
            if finnhubMatches.isEmpty {
                merged.append(mappedAsset)
            } else {
                merged.append(contentsOf: finnhubMatches.map { match in
                    MarketAsset(
                        symbol: match.symbol,
                        name: match.name.isEmpty ? mappedAsset.name : match.name,
                        exchange: match.exchange.isEmpty ? mappedAsset.exchange : match.exchange,
                        currencyCode: match.currencyCode,
                        isin: originalQuery.isLikelyISIN ? originalQuery.uppercased() : mappedAsset.isin,
                        wkn: originalQuery.isLikelyWKN ? originalQuery.uppercased() : mappedAsset.wkn,
                        figi: mappedAsset.figi,
                        source: .finnhub
                    )
                })
            }
        }

        return Array(merged.uniquedByID().prefix(12))
    }
}

struct FinnhubMarketDataClient: MarketDataClient {
    let apiKey: String
    let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = MarketDataURLSessionFactory.shared) {
        self.apiKey = apiKey.trimmedForDisplay
        self.urlSession = urlSession
    }

    func searchAssets(query: String) async throws -> [MarketAsset] {
        guard !apiKey.isEmpty else { throw MarketDataError.missingAPIKey }
        let data = try await get(path: "search", queryItems: [
            URLQueryItem(name: "q", value: query)
        ])
        let decoded = try Self.decodeSearchResponse(data)
        let matches = decoded.result
            .filter { !$0.symbol.trimmedForDisplay.isEmpty }
            .prefix(16)
            .map { match in
                MarketAsset(
                    symbol: match.symbol,
                    name: match.description.nilIfEmpty ?? match.displaySymbol.nilIfEmpty ?? match.symbol,
                    exchange: match.displaySymbol.exchangeHint,
                    currencyCode: match.displaySymbol.guessedCurrencyCode,
                    source: .finnhub
                )
            }

        return Array(matches).uniquedByID()
    }

    func quote(for asset: MarketAsset) async throws -> MarketQuote {
        guard !apiKey.isEmpty else { throw MarketDataError.missingAPIKey }
        let data = try await get(path: "quote", queryItems: [
            URLQueryItem(name: "symbol", value: asset.symbol)
        ])
        let decoded = try Self.decodeQuoteResponse(data)
        guard decoded.c.isFinite, decoded.c > 0 else {
            throw MarketDataError.quoteUnavailable
        }

        let timestamp = decoded.t > 0 ? Date(timeIntervalSince1970: TimeInterval(decoded.t)) : nil
        let isStale = timestamp.map { abs($0.timeIntervalSinceNow) > 60 * 60 * 24 } ?? true

        return MarketQuote(
            symbol: asset.symbol,
            price: decoded.c,
            currencyCode: asset.currencyCode,
            timestamp: timestamp,
            source: .finnhub,
            isStale: isStale,
            statusMessage: isStale ? "Quote timestamp is older than 24 hours." : nil
        )
    }

    static func decodeSearchResponse(_ data: Data) throws -> FinnhubSearchResponse {
        do {
            return try JSONDecoder().decode(FinnhubSearchResponse.self, from: data)
        } catch {
            let apiError = try? JSONDecoder().decode(FinnhubAPIError.self, from: data)
            throw apiError?.marketDataError ?? MarketDataError.invalidResponse("Could not decode Finnhub search results.")
        }
    }

    static func decodeQuoteResponse(_ data: Data) throws -> FinnhubQuoteResponse {
        do {
            let quote = try JSONDecoder().decode(FinnhubQuoteResponse.self, from: data)
            if quote.c == 0, quote.t == 0 {
                let apiError = try? JSONDecoder().decode(FinnhubAPIError.self, from: data)
                if let apiError {
                    throw apiError.marketDataError
                }
            }
            return quote
        } catch let marketDataError as MarketDataError {
            throw marketDataError
        } catch {
            let apiError = try? JSONDecoder().decode(FinnhubAPIError.self, from: data)
            throw apiError?.marketDataError ?? MarketDataError.invalidResponse("Could not decode Finnhub quote.")
        }
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "finnhub.io"
        components.path = "/api/v1/\(path)"
        components.queryItems = queryItems + [URLQueryItem(name: "token", value: apiKey)]

        guard let url = components.url else { throw MarketDataError.invalidURL }

        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketDataError.invalidResponse("The market-data service returned an invalid response.")
        }
        guard httpResponse.statusCode != 429 else { throw MarketDataError.rateLimited }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.badStatusCode(httpResponse.statusCode)
        }
        return data
    }
}

struct OpenFIGIIdentifierResolver: Sendable {
    enum IdentifierType: String, Sendable {
        case isin = "ID_ISIN"
        case wkn = "ID_WERTPAPIER"
    }

    let apiKey: String?
    let urlSession: URLSession

    init(apiKey: String? = nil, urlSession: URLSession = MarketDataURLSessionFactory.shared) {
        self.apiKey = apiKey?.trimmedForDisplay.nilIfEmpty
        self.urlSession = urlSession
    }

    func resolveIdentifier(_ identifier: String, idType: IdentifierType) async throws -> [MarketAsset] {
        let payload = [
            OpenFIGIMappingRequest(
                idType: idType.rawValue,
                idValue: identifier.trimmedForDisplay.uppercased(),
                marketSecDes: "Equity"
            )
        ]

        guard let url = URL(string: "https://api.openfigi.com/v3/mapping") else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-OPENFIGI-APIKEY")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarketDataError.invalidResponse("OpenFIGI returned an invalid response.")
        }
        guard httpResponse.statusCode != 429 else { throw MarketDataError.rateLimited }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.badStatusCode(httpResponse.statusCode)
        }

        return try Self.decodeMappingResponse(data, originalIdentifier: identifier, idType: idType)
    }

    static func decodeMappingResponse(
        _ data: Data,
        originalIdentifier: String,
        idType: IdentifierType
    ) throws -> [MarketAsset] {
        let decoded = try JSONDecoder().decode([OpenFIGIMappingResponse].self, from: data)
        let original = originalIdentifier.trimmedForDisplay.uppercased()

        let instruments = decoded.flatMap { response in
            response.data ?? []
        }
        let equityInstruments = instruments.filter { item in
            item.marketSector?.caseInsensitiveCompare("Equity") == .orderedSame || item.marketSector == nil
        }
        let assets = equityInstruments.prefix(16).map { item in
            MarketAsset(
                symbol: item.ticker ?? item.securityDescription ?? "",
                name: item.name ?? item.securityDescription ?? item.ticker ?? original,
                exchange: item.exchCode ?? "",
                currencyCode: (item.exchCode ?? "").guessedCurrencyCodeFromExchange,
                isin: idType == .isin ? original : nil,
                wkn: idType == .wkn ? original : nil,
                figi: item.figi,
                source: .openFIGI
            )
        }

        return Array(assets).uniquedByID()
    }
}

enum MarketDataClientFactory {
    static func make(bundle: Bundle = .main, includeSavedKeys: Bool = true) -> CompositeMarketDataClient? {
        make(
            finnhubAPIKey: nil,
            openFIGIAPIKey: nil,
            includeSavedKeys: includeSavedKeys,
            bundle: bundle
        )
    }

    static func make(
        finnhubAPIKey: String?,
        openFIGIAPIKey: String?,
        includeSavedKeys: Bool = true,
        bundle: Bundle = .main
    ) -> CompositeMarketDataClient? {
        let explicitFinnhubAPIKey = sanitizedAPIKey(finnhubAPIKey)
        let explicitOpenFIGIAPIKey = sanitizedAPIKey(openFIGIAPIKey)
        let savedFinnhubAPIKey = explicitFinnhubAPIKey == nil && includeSavedKeys ? try? APIKeyStore.string(for: .finnhub) : nil
        let savedOpenFIGIAPIKey = explicitOpenFIGIAPIKey == nil && includeSavedKeys ? try? APIKeyStore.string(for: .openFIGI) : nil

        guard let resolvedFinnhubAPIKey = explicitFinnhubAPIKey
            ?? sanitizedAPIKey(savedFinnhubAPIKey)
            ?? apiKey(named: "FINNHUB_API_KEY", bundle: bundle)
        else {
            return nil
        }

        return CompositeMarketDataClient(
            finnhub: FinnhubMarketDataClient(apiKey: resolvedFinnhubAPIKey),
            openFIGI: OpenFIGIIdentifierResolver(
                apiKey: explicitOpenFIGIAPIKey
                    ?? sanitizedAPIKey(savedOpenFIGIAPIKey)
                    ?? apiKey(named: "OPENFIGI_API_KEY", bundle: bundle)
            )
        )
    }

    static func apiKey(named key: String, bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        return sanitizedAPIKey(value)
    }

    static func sanitizedAPIKey(_ value: String?) -> String? {
        APIKeyValidator.sanitizedAPIKey(value)
    }
}

struct FinnhubSearchResponse: Decodable, Equatable {
    let count: Int
    let result: [FinnhubSearchMatch]
}

struct FinnhubSearchMatch: Decodable, Equatable {
    let description: String
    let displaySymbol: String
    let symbol: String
    let type: String?
}

struct FinnhubQuoteResponse: Decodable, Equatable {
    let c: Double
    let d: Double?
    let dp: Double?
    let h: Double?
    let l: Double?
    let o: Double?
    let pc: Double?
    let t: Int
}

private struct FinnhubAPIError: Decodable {
    let error: String?

    var marketDataError: MarketDataError {
        guard let error else {
            return .invalidResponse("Finnhub returned an error.")
        }
        if error.localizedCaseInsensitiveContains("limit") {
            return .rateLimited
        }
        return .invalidResponse(error)
    }
}

private struct OpenFIGIMappingRequest: Encodable {
    let idType: String
    let idValue: String
    let marketSecDes: String
}

private struct OpenFIGIMappingResponse: Decodable {
    let data: [OpenFIGIInstrument]?
    let warning: String?
    let error: String?
}

private struct OpenFIGIInstrument: Decodable {
    let figi: String?
    let securityType: String?
    let marketSector: String?
    let ticker: String?
    let name: String?
    let exchCode: String?
    let securityType2: String?
    let securityDescription: String?
}

private extension Array where Element == MarketAsset {
    func uniquedByID() -> [MarketAsset] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private extension Array where Element == Error {
    var actionableMarketDataError: Error? {
        first { error in
            guard let marketDataError = error as? MarketDataError else {
                return true
            }

            switch marketDataError {
            case .noResults, .quoteUnavailable:
                return false
            case .missingAPIKey, .invalidURL, .rateLimited, .badStatusCode, .invalidResponse:
                return true
            }
        }
    }
}

extension String {
    var trimmedForDisplay: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var isLikelyISIN: Bool {
        let value = trimmedForDisplay.uppercased()
        guard value.count == 12 else { return false }
        let prefix = value.prefix(2)
        let suffix = value.dropFirst(2)
        return prefix.allSatisfy(\.isLetter) && suffix.allSatisfy { $0.isLetter || $0.isNumber }
    }

    var isLikelyWKN: Bool {
        let value = trimmedForDisplay.uppercased()
        guard value.count == 6, !isLikelyISIN else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber }
    }

    var exchangeHint: String {
        guard let suffix = split(separator: ".").last, contains(".") else {
            return "Global"
        }

        switch suffix.uppercased() {
        case "US":
            return "US"
        case "DE":
            return "Germany"
        case "L":
            return "London"
        case "TO", "V":
            return "Canada"
        case "PA":
            return "Paris"
        case "AS":
            return "Amsterdam"
        case "SW":
            return "Switzerland"
        default:
            return String(suffix).uppercased()
        }
    }

    var guessedCurrencyCode: String {
        guard let suffix = split(separator: ".").last, contains(".") else {
            return BuybackCalculator.defaultCurrencyCode
        }

        switch suffix.uppercased() {
        case "DE", "F", "BE", "MU", "HM", "SG", "PA", "AS", "MC", "MI":
            return "EUR"
        case "L":
            return "GBP"
        case "SW":
            return "CHF"
        case "TO", "V":
            return "CAD"
        case "T":
            return "JPY"
        case "HK":
            return "HKD"
        case "AX":
            return "AUD"
        default:
            return BuybackCalculator.defaultCurrencyCode
        }
    }

    var guessedCurrencyCodeFromExchange: String {
        switch uppercased() {
        case "GY", "GR", "DE", "F", "FP", "NA", "IM", "SM", "EU":
            return "EUR"
        case "LN", "LSE", "UK":
            return "GBP"
        case "SW", "VX":
            return "CHF"
        case "CN", "CT", "TO", "V":
            return "CAD"
        case "JP", "JT":
            return "JPY"
        case "HK":
            return "HKD"
        case "AU", "AT":
            return "AUD"
        default:
            return BuybackCalculator.defaultCurrencyCode
        }
    }
}
