import Foundation

enum TaxLotDraftStorage {
    static let storageKey = "buybackCalculator.taxLots"

    static func decode(_ rawValue: String) -> [TaxLot] {
        guard let data = rawValue.data(using: .utf8),
              let lots = try? JSONDecoder().decode([TaxLot].self, from: data)
        else {
            return []
        }

        return lots
    }

    static func encode(_ lots: [TaxLot]) -> String {
        guard let data = try? JSONEncoder().encode(lots),
              let rawValue = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return rawValue
    }

    static func legacyLots(
        lot1Shares: String,
        lot1Basis: String,
        lot2Shares: String,
        lot2Basis: String,
        lot3Shares: String,
        lot3Basis: String
    ) -> [TaxLot] {
        [
            legacyLot(sharesText: lot1Shares, basisText: lot1Basis),
            legacyLot(sharesText: lot2Shares, basisText: lot2Basis),
            legacyLot(sharesText: lot3Shares, basisText: lot3Basis)
        ].compactMap { $0 }
    }

    private static func legacyLot(sharesText: String, basisText: String) -> TaxLot? {
        guard let shares = BuybackCalculator.parseDecimal(sharesText),
              let basis = BuybackCalculator.parseDecimal(basisText)
        else {
            return nil
        }

        let lot = TaxLot(shares: shares, averageCostBasis: basis)
        return lot.isValid ? lot : nil
    }
}
