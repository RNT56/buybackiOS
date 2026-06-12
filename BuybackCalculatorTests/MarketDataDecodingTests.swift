import Foundation
import XCTest

final class MarketDataDecodingTests: XCTestCase {
    func testFinnhubSearchDecoding() throws {
        let data = Data(
            """
            {
              "count": 2,
              "result": [
                {
                  "description": "APPLE INC",
                  "displaySymbol": "AAPL",
                  "symbol": "AAPL",
                  "type": "Common Stock"
                },
                {
                  "description": "APPLE INC XETRA",
                  "displaySymbol": "APC.DE",
                  "symbol": "APC.DE",
                  "type": "Common Stock"
                }
              ]
            }
            """.utf8
        )

        let response = try FinnhubMarketDataClient.decodeSearchResponse(data)

        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.result.first?.symbol, "AAPL")
        XCTAssertEqual(response.result.last?.displaySymbol, "APC.DE")
    }

    func testFinnhubQuoteDecoding() throws {
        let data = Data(
            """
            {
              "c": 185.12,
              "d": 1.2,
              "dp": 0.65,
              "h": 187.0,
              "l": 181.4,
              "o": 182.0,
              "pc": 183.92,
              "t": 1781197200
            }
            """.utf8
        )

        let quote = try FinnhubMarketDataClient.decodeQuoteResponse(data)

        XCTAssertEqual(quote.c, 185.12, accuracy: 0.0001)
        XCTAssertEqual(quote.t, 1_781_197_200)
    }

    func testFinnhubRateLimitPayloadDecoding() {
        let data = Data(#"{"error":"API limit reached. Please try again later."}"#.utf8)

        XCTAssertThrowsError(try FinnhubMarketDataClient.decodeQuoteResponse(data)) { error in
            XCTAssertEqual(error as? MarketDataError, .rateLimited)
        }
    }

    func testOpenFIGIISINMappingDecoding() throws {
        let data = Data(
            """
            [
              {
                "data": [
                  {
                    "figi": "BBG000B9XRY4",
                    "securityType": "Common Stock",
                    "marketSector": "Equity",
                    "ticker": "AAPL",
                    "name": "APPLE INC",
                    "exchCode": "US",
                    "securityType2": "Common Stock",
                    "securityDescription": "AAPL"
                  }
                ]
              }
            ]
            """.utf8
        )

        let assets = try OpenFIGIIdentifierResolver.decodeMappingResponse(
            data,
            originalIdentifier: "US0378331005",
            idType: .isin
        )

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets[0].symbol, "AAPL")
        XCTAssertEqual(assets[0].isin, "US0378331005")
        XCTAssertEqual(assets[0].figi, "BBG000B9XRY4")
    }

    func testOpenFIGINoMatchDecoding() throws {
        let data = Data(#"[{"warning":"No identifier found."}]"#.utf8)

        let assets = try OpenFIGIIdentifierResolver.decodeMappingResponse(
            data,
            originalIdentifier: "123456",
            idType: .wkn
        )

        XCTAssertTrue(assets.isEmpty)
    }
}
