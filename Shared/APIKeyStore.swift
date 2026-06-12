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
    private static let sharedAccessGroupIdentifier = "com.schtack.BuybackCalculator.apiKeys"

    static func string(for kind: APIKeyKind) throws -> String? {
        var firstError: Error?

        if let accessGroup = sharedAccessGroup {
            do {
                if let value = try string(for: kind, accessGroup: accessGroup) {
                    return value
                }
            } catch {
                firstError = error
            }
        }

        do {
            return try string(for: kind, accessGroup: nil)
        } catch {
            throw firstError ?? error
        }
    }

    static func set(_ value: String?, for kind: APIKeyKind) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            try delete(kind)
            return
        }

        var firstError: Error?

        if let accessGroup = sharedAccessGroup {
            do {
                try set(trimmed, for: kind, accessGroup: accessGroup)
                try? delete(kind, accessGroup: nil)
                return
            } catch {
                firstError = error
            }
        }

        do {
            try set(trimmed, for: kind, accessGroup: nil)
        } catch {
            throw firstError ?? error
        }
    }

    static func delete(_ kind: APIKeyKind) throws {
        var firstError: Error?
        var deletedOrMissing = false

        for accessGroup in [sharedAccessGroup, nil] {
            do {
                try delete(kind, accessGroup: accessGroup)
                deletedOrMissing = true
            } catch {
                firstError = firstError ?? error
            }
        }

        if !deletedOrMissing, let firstError {
            throw firstError
        }
    }

    private static func string(for kind: APIKeyKind, accessGroup: String?) throws -> String? {
        var query = baseQuery(for: kind, accessGroup: accessGroup)
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

    private static func set(_ value: String, for kind: APIKeyKind, accessGroup: String?) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: kind, accessGroup: accessGroup)
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

    private static func delete(_ kind: APIKeyKind, accessGroup: String?) throws {
        let status = SecItemDelete(baseQuery(for: kind, accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.unhandledStatus(status)
        }
    }

    private static func baseQuery(for kind: APIKeyKind, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private static var sharedAccessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else {
            return nil
        }

        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty,
              !trimmedPrefix.hasPrefix("$(")
        else {
            return nil
        }

        return trimmedPrefix + sharedAccessGroupIdentifier
    }
}
