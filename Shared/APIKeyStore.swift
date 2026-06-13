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
    case invalidFormat(APIKeyKind, String)
    case migrationFailed(APIKeyKind, Error)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain returned status \(status)."
        case .invalidData:
            return "The saved API key could not be read."
        case .invalidFormat(let kind, let reason):
            return "\(kind.label) API key is invalid. \(reason)"
        case .migrationFailed(let kind, let error):
            return "\(kind.label) API key could not be migrated into Keychain: \(error.localizedDescription)"
        }
    }
}

enum APIKeyValidator {
    static let maximumLength = 512

    static func sanitizedAPIKey(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmedForDisplay
        guard !trimmed.isEmpty,
              validationMessage(forSanitizedValue: trimmed) == nil
        else {
            return nil
        }

        return trimmed
    }

    static func validatedAPIKey(_ value: String?, for kind: APIKeyKind) throws -> String? {
        let trimmed = value?.trimmedForDisplay ?? ""
        guard !trimmed.isEmpty else {
            return nil
        }

        if let message = validationMessage(forSanitizedValue: trimmed) {
            throw APIKeyStoreError.invalidFormat(kind, message)
        }

        return trimmed
    }

    static func validationMessage(for value: String?) -> String? {
        let trimmed = value?.trimmedForDisplay ?? ""
        guard !trimmed.isEmpty else { return nil }
        return validationMessage(forSanitizedValue: trimmed)
    }

    private static func validationMessage(forSanitizedValue value: String) -> String? {
        let lowercased = value.lowercased()
        if value.hasPrefix("$(") || lowercased.contains("your_") || lowercased.contains("placeholder") {
            return "Enter a real provider key, not a placeholder."
        }

        if value.count > maximumLength {
            return "Keys must be \(maximumLength) characters or fewer."
        }

        if value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return "Keys cannot contain spaces or line breaks."
        }

        if value.unicodeScalars.contains(where: { $0.value < 0x21 || $0.value > 0x7E }) {
            return "Keys must use printable ASCII characters."
        }

        return nil
    }
}

enum APIKeyStore {
    private static let service = "com.schtack.BuybackCalculator.apiKeys"
    private static let sharedAccessGroupIdentifier = "com.schtack.BuybackCalculator.apiKeys"
    private static let fallbackStoragePrefix = "buybackCalculator.apiKeys."

    static func string(for kind: APIKeyKind) throws -> String? {
        var firstError: Error?

        if let accessGroup = sharedAccessGroup {
            do {
                if let value = try string(for: kind, accessGroup: accessGroup) {
                    deleteFallbackString(for: kind)
                    return try validateStoredValue(value, for: kind, accessGroup: accessGroup)
                }
            } catch {
                firstError = error
            }
        }

        do {
            if let value = try string(for: kind, accessGroup: nil) {
                let validatedValue = try validateStoredValue(value, for: kind, accessGroup: nil)
                deleteFallbackString(for: kind)
                if let accessGroup = sharedAccessGroup {
                    do {
                        try set(validatedValue, for: kind, accessGroup: accessGroup)
                        try? delete(kind, accessGroup: nil)
                    } catch {
                        firstError = firstError ?? error
                    }
                }
                return validatedValue
            }
        } catch {
            firstError = firstError ?? error
        }

        if let migrated = try migrateLegacyFallbackIfNeeded(for: kind) {
            return migrated
        }

        if let firstError {
            throw firstError
        }

        return nil
    }

    static func set(_ value: String?, for kind: APIKeyKind) throws {
        guard let trimmed = try APIKeyValidator.validatedAPIKey(value, for: kind) else {
            try delete(kind)
            return
        }

        var firstError: Error?

        if let accessGroup = sharedAccessGroup {
            do {
                try set(trimmed, for: kind, accessGroup: accessGroup)
                try? delete(kind, accessGroup: nil)
                deleteFallbackString(for: kind)
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

        deleteFallbackString(for: kind)
    }

    static func delete(_ kind: APIKeyKind) throws {
        deleteFallbackString(for: kind)

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

    private static func validateStoredValue(
        _ value: String,
        for kind: APIKeyKind,
        accessGroup: String?
    ) throws -> String {
        do {
            guard let validatedValue = try APIKeyValidator.validatedAPIKey(value, for: kind) else {
                try? delete(kind, accessGroup: accessGroup)
                throw APIKeyStoreError.invalidData
            }
            return validatedValue
        } catch {
            try? delete(kind, accessGroup: accessGroup)
            throw error
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

    private static func fallbackString(for kind: APIKeyKind) -> String? {
        let value = BuybackSharedStorage.userDefaults.string(forKey: fallbackStorageKey(for: kind))
        return APIKeyValidator.sanitizedAPIKey(value)
    }

    private static func deleteFallbackString(for kind: APIKeyKind) {
        let userDefaults = BuybackSharedStorage.userDefaults
        userDefaults.removeObject(forKey: fallbackStorageKey(for: kind))
        UserDefaults.standard.removeObject(forKey: fallbackStorageKey(for: kind))
    }

    private static func fallbackStorageKey(for kind: APIKeyKind) -> String {
        fallbackStoragePrefix + kind.rawValue
    }

    private static func migrateLegacyFallbackIfNeeded(for kind: APIKeyKind) throws -> String? {
        guard let legacyValue = fallbackString(for: kind) else {
            return nil
        }

        do {
            try set(legacyValue, for: kind)
            deleteFallbackString(for: kind)
            return legacyValue
        } catch {
            throw APIKeyStoreError.migrationFailed(kind, error)
        }
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
