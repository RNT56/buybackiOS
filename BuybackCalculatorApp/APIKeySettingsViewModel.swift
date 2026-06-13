import Combine
import Foundation

@MainActor
final class APIKeySettingsViewModel: ObservableObject {
    @Published var finnhubAPIKey = ""
    @Published var openFIGIAPIKey = ""
    @Published var statusMessage: String?
    @Published var isWorking = false
    @Published private(set) var savedFinnhubAPIKey = ""
    @Published private(set) var savedOpenFIGIAPIKey = ""

    var effectiveFinnhubAPIKey: String? {
        MarketDataClientFactory.sanitizedAPIKey(finnhubAPIKey)
            ?? MarketDataClientFactory.sanitizedAPIKey(savedFinnhubAPIKey)
    }

    var effectiveOpenFIGIAPIKey: String? {
        MarketDataClientFactory.sanitizedAPIKey(openFIGIAPIKey)
            ?? MarketDataClientFactory.sanitizedAPIKey(savedOpenFIGIAPIKey)
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
        validationMessage == nil && !isWorking
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

    var hasUnsavedFinnhubAPIKey: Bool {
        guard let draftKey = MarketDataClientFactory.sanitizedAPIKey(finnhubAPIKey) else {
            return false
        }

        return draftKey != MarketDataClientFactory.sanitizedAPIKey(savedFinnhubAPIKey)
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

        applyLoadedKeys(
            finnhubAPIKey: loadedKeys.finnhubAPIKey,
            openFIGIAPIKey: loadedKeys.openFIGIAPIKey
        )
        statusMessage = loadedKeys.errorMessage
    }

    func saveAsync() async {
        let validatedFinnhubKey: String?
        let validatedOpenFIGIKey: String?

        do {
            validatedFinnhubKey = try APIKeyValidator.validatedAPIKey(finnhubAPIKey, for: .finnhub)
            validatedOpenFIGIKey = try APIKeyValidator.validatedAPIKey(openFIGIAPIKey, for: .openFIGI)
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        isWorking = true
        let result = await Task.detached(priority: .utility) {
            do {
                try APIKeyStore.set(validatedFinnhubKey, for: .finnhub)
                try APIKeyStore.set(validatedOpenFIGIKey, for: .openFIGI)
                return nil as String?
            } catch {
                return error.localizedDescription
            }
        }.value
        isWorking = false

        if let result {
            statusMessage = result
            return
        }

        applyLoadedKeys(
            finnhubAPIKey: validatedFinnhubKey ?? "",
            openFIGIAPIKey: validatedOpenFIGIKey ?? ""
        )
        statusMessage = "API keys saved securely in Keychain."
    }

    func clearAsync() async {
        isWorking = true
        let result = await Task.detached(priority: .utility) {
            do {
                try APIKeyStore.delete(.finnhub)
                try APIKeyStore.delete(.openFIGI)
                return nil as String?
            } catch {
                return error.localizedDescription
            }
        }.value
        isWorking = false

        if let result {
            statusMessage = result
            return
        }

        applyLoadedKeys(finnhubAPIKey: "", openFIGIAPIKey: "")
        statusMessage = "API keys cleared."
    }

    private func applyLoadedKeys(finnhubAPIKey: String, openFIGIAPIKey: String) {
        savedFinnhubAPIKey = finnhubAPIKey
        savedOpenFIGIAPIKey = openFIGIAPIKey
        self.finnhubAPIKey = finnhubAPIKey
        self.openFIGIAPIKey = openFIGIAPIKey
    }
}
