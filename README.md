# BuybackCalculator

An iOS 26+ SwiftUI app and WidgetKit extension for a stock buy-back calculator with asset lookup, live quote autofill, and manual fallback pricing.

## What it calculates

Given:

- An asset selected by name, ticker, ISIN, or WKN
- Current or fallback sell price per share
- Current gain percentage at that price

It assumes:

- 27% tax on realized gains by default
- Target to buy back at least 2.5% more shares than before selling by default

Formula:

```text
costBasis = sellPrice / (1 + gainPercent / 100)
taxableGain = max(0, sellPrice - costBasis)
tax = taxableGain * taxRate
afterTaxCash = sellPrice - tax
maximumBuybackPrice = afterTaxCash / (1 + targetExtraSharesPercent / 100)
```

The app has a simple flow for asset lookup, auto-filled price, and gain input. The advanced section can override the price and adjust shares, tax rate, and target extra shares.

## Market Data

The app uses:

- Finnhub for autocomplete and current quotes
- OpenFIGI as a best-effort fallback for ISIN and WKN mapping

You can add keys directly in the app under `API Keys`. App-entered keys are stored in the iOS Keychain and are preferred over bundled build settings.

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

1. In-app Keychain key
2. Bundled `Config/Secrets.xcconfig` key
3. Manual/fallback pricing

## Project

The Xcode project is generated from `project.yml`:

- App target: `BuybackCalculator`
- Widget extension target: `BuybackWidgetExtension`
- Unit test target: `BuybackCalculatorTests`
- Minimum deployment target: iOS 26.0
- Shared calculation and market data sources: `Shared/`

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

The widget tries to fetch a live quote on its timeline refresh and falls back to the configured price when the API key, network, rate limit, or quote is unavailable.
