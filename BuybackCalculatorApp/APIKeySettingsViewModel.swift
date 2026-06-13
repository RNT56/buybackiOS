import Combine
import Foundation

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

    var validationMessage: String? {
        if let message = APIKeyValidator.validationMessage(for: finnhubAPIKey) {
            return "Finnhub: \(message)"
        }

        if let message = APIKeyValidator.validationMessage(for: openFIGIAPIKey) {
            return "OpenFIGI: \(message)"
        }

        return nil
    }

    var canSave: Bool {
        validationMessage == nil
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

    func load() {
        do {
            finnhubAPIKey = try APIKeyStore.string(for: .finnhub) ?? ""
            openFIGIAPIKey = try APIKeyStore.string(for: .openFIGI) ?? ""
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadAsync() async {
        let loadedKeys = await Task.detached(priority: .utility) {
            do {
                return (
                    finnhubAPIKey: try APIKeyStore.string(for: .finnhub) ?? "",
                    openFIGIAPIKey: try APIKeyStore.string(for: .openFIGI) ?? "",
                    errorMessage: nil as String?
                )
            } catch {
                return (
                    finnhubAPIKey: "",
                    openFIGIAPIKey: "",
                    errorMessage: error.localizedDescription
                )
            }
        }.value

        finnhubAPIKey = loadedKeys.finnhubAPIKey
        openFIGIAPIKey = loadedKeys.openFIGIAPIKey
        statusMessage = loadedKeys.errorMessage
    }

    func save() {
        do {
            let validatedFinnhubKey = try APIKeyValidator.validatedAPIKey(finnhubAPIKey, for: .finnhub)
            let validatedOpenFIGIKey = try APIKeyValidator.validatedAPIKey(openFIGIAPIKey, for: .openFIGI)
            try APIKeyStore.set(validatedFinnhubKey, for: .finnhub)
            try APIKeyStore.set(validatedOpenFIGIKey, for: .openFIGI)
            load()
            statusMessage = "API keys saved securely in Keychain."
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
