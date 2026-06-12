import Foundation
import Security

enum APIKeyKind: String, CaseIterable {
    case finnhub = "finnhub"
    case openFIGI = "openfigi"

    var label: String {
        switch self {
        case .finnhub:
            return "Finnhub"
        case .openFIGI:
            return "OpenFIGI"
        }
    }
}

enum APIKeyStoreError: Error, LocalizedError {
    case unhandledStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain returned status \(status)."
        case .invalidData:
            return "The saved API key could not be read."
        }
    }
}

enum APIKeyStore {
    private static let service = "com.schtack.BuybackCalculator.apiKeys"

    static func string(for kind: APIKeyKind) throws -> String? {
        var query = baseQuery(for: kind)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                throw APIKeyStoreError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw APIKeyStoreError.unhandledStatus(status)
        }
    }

    static func set(_ value: String?, for kind: APIKeyKind) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            try delete(kind)
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery(for: kind)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.unhandledStatus(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.unhandledStatus(addStatus)
        }
    }

    static func delete(_ kind: APIKeyKind) throws {
        let status = SecItemDelete(baseQuery(for: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.unhandledStatus(status)
        }
    }

    private static func baseQuery(for kind: APIKeyKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
    }
}

@MainActor
final class APIKeySettingsViewModel: ObservableObject {
    @Published var finnhubAPIKey = ""
    @Published var openFIGIAPIKey = ""
    @Published var statusMessage: String?

    var effectiveFinnhubAPIKey: String? {
        MarketDataClientFactory.sanitizedAPIKey(finnhubAPIKey)
    }

    var effectiveOpenFIGIAPIKey: String? {
        MarketDataClientFactory.sanitizedAPIKey(openFIGIAPIKey)
    }

    var hasRuntimeFinnhubAPIKey: Bool {
        effectiveFinnhubAPIKey != nil
    }

    var hasBundledFinnhubAPIKey: Bool {
        MarketDataClientFactory.apiKey(named: "FINNHUB_API_KEY") != nil
    }

    var hasUsableFinnhubAPIKey: Bool {
        hasRuntimeFinnhubAPIKey || hasBundledFinnhubAPIKey
    }

    init() {
        load()
    }

    func load() {
        do {
            finnhubAPIKey = try APIKeyStore.string(for: .finnhub) ?? ""
            openFIGIAPIKey = try APIKeyStore.string(for: .openFIGI) ?? ""
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func save() {
        do {
            try APIKeyStore.set(finnhubAPIKey, for: .finnhub)
            try APIKeyStore.set(openFIGIAPIKey, for: .openFIGI)
            load()
            statusMessage = "API keys saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clear() {
        do {
            try APIKeyStore.delete(.finnhub)
            try APIKeyStore.delete(.openFIGI)
            load()
            statusMessage = "API keys cleared."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
