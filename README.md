# BuybackCalculator

An iOS 26+ SwiftUI app and WidgetKit extension for stock buy-back planning with asset lookup, live quote autofill, manual fallback pricing, tax-aware calculations, saved scenarios, price alerts, and an iPad split layout.

## Features

- Asset lookup by name, ticker, ISIN, or WKN with Finnhub quotes and OpenFIGI identifier fallback
- Manual price override when live pricing is unavailable or intentionally bypassed
- Tax profiles for Germany, US long-term, US short-term, and custom tax rates
- Optional tax currency and FX conversion for reporting tax in a different currency
- Gain-driven basis or multi-lot weighted average basis with up to three editable tax lots
- Sell fees, buy fees, slippage buffer, and extra-share target controls
- Price sensitivity table that preserves the current cost basis while modeling price moves
- Saved scenarios that preserve asset, pricing, tax profile, FX, fees, slippage, and tax-lot inputs
- Price alerts stored on device and checked when a selected asset quote refreshes
- Regular-width iPad split layout with inputs on the left and results on the right
- Configurable Home Screen widget with live quote refresh, fallback price, tax profile, FX, fees, and deep links into the app

## What It Calculates

Given:

- Current or fallback sell price per share
- Either a gain percentage or weighted tax-lot cost basis
- Shares to sell
- Tax profile, tax currency, and FX rate to the tax currency
- Optional sell fees, buy fees, and slippage buffer

Defaults:

- Germany tax profile at 27%
- Target to buy back at least 2.5% more shares than before selling
- No trading fees, no slippage, and 1.0 FX rate

Formula:

```text
costBasis = sellPrice / (1 + gainPercent / 100)
costBasis = weightedAverage(lotShares * lotCostBasis) when tax lots are enabled
grossProceeds = sellPrice * sharesToSell
netSaleProceeds = grossProceeds - sellFeeTotal
taxableGain = max(0, netSaleProceeds - costBasis * sharesToSell)
taxableGainInTaxCurrency = taxableGain * fxRateToTaxCurrency
taxInTaxCurrency = taxableGainInTaxCurrency * taxRate
tax = taxInTaxCurrency / fxRateToTaxCurrency
afterTaxCash = netSaleProceeds - tax
cashAvailableForBuyback = max(0, afterTaxCash - buyFeeTotal)
targetShareCount = sharesToSell * (1 + targetExtraSharesPercent / 100)
maximumBuybackPrice = cashAvailableForBuyback / targetShareCount / (1 + slippagePercent / 100)
```

The advanced section controls manual pricing, tax profile, custom tax rate, tax currency, FX rate, shares, target extra shares, fees, slippage, and tax lots. When tax lots are enabled, the gain field is disabled and the calculator derives gain from the weighted basis.

## Market Data

The app uses:

- Finnhub for autocomplete and current quotes
- OpenFIGI as a best-effort fallback for ISIN and WKN mapping

You can add keys directly in the app under `Settings`. App-entered keys are stored in a shared iOS Keychain access group so the app and widget can use the same runtime keys. Runtime keys are preferred over bundled build settings.

For build-time bundled keys, create a local config file:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Then add at least:

```text
FINNHUB_API_KEY = your_finnhub_key
```

`OPENFIGI_API_KEY` is optional; unauthenticated OpenFIGI requests work with lower rate limits. `Config/Secrets.xcconfig` is ignored by git. If no Finnhub key is available, the app and widget still work with manual/fallback prices.

Runtime key priority:

1. Shared Keychain key saved in the app
2. Bundled `Config/Secrets.xcconfig` key
3. Manual/fallback pricing

## Project

The Xcode project is generated from `project.yml`:

- App target: `BuybackCalculator`
- Widget extension target: `BuybackWidgetExtension`
- Unit test target: `BuybackCalculatorTests`
- Minimum deployment target: iOS 26.0
- Shared calculation and market data sources: `Shared/`
- Shared runtime API keys use `keychain-access-groups` entitlements generated from `project.yml`

Regenerate the project after changing target membership, build settings, or Info.plist properties:

```sh
xcodegen generate
```

Build for the iOS 26.5 simulator:

```sh
xcodebuild -project BuybackCalculator.xcodeproj \
  -scheme BuybackCalculator \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build
```

Run tests:

```sh
xcodebuild -project BuybackCalculator.xcodeproj \
  -scheme BuybackCalculator \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  test
```

## How To Use The Widget

1. Build and install the app.
2. Add the `Buy-Back Calculator` widget to your Home Screen.
3. Long-press the widget.
4. Tap `Edit Widget`.
5. Enter:
   - Stock Symbol
   - Gain %
   - Fallback Price
   - Optional tax profile, tax rate, tax currency, FX rate, extra-share target, sell fees, buy fees, and slippage

The widget tries to fetch a live quote on its timeline refresh and falls back to the configured price when the API key, network, rate limit, or quote is unavailable. Tapping the widget opens the app for the configured symbol and carries supported widget inputs through the app deep link.

## Price Alerts

Alerts are stored locally in the app. Use the `Price alert` section to arm an alert at the calculated buy-back limit or a custom price. Alerts are evaluated when a selected asset quote is fetched or refreshed; if the current price is at or below the target, the app schedules a local notification. Repeated triggers are throttled for six hours per symbol.
