# Buyback Calculator

<p align="center">
  <strong>Know the price where selling today and buying back later still works.</strong>
</p>

<p align="center">
  Buyback Calculator is a local-first iOS 26+ planning app for investors who want to model taxes, fees, FX, tax lots, live prices, saved scenarios, widgets, and alerts before a sell-and-rebuy decision turns into guesswork.
</p>

<p align="center">
  <a href="#the-pain-point">Pain Point</a> ·
  <a href="#the-solution">Solution</a> ·
  <a href="#what-users-get">User Value</a> ·
  <a href="#product-tour">Product Tour</a> ·
  <a href="#local-first-trust-model">Trust Model</a> ·
  <a href="#developer-setup">Developer Setup</a>
</p>

---

## The Pain Point

Selling a winning position looks simple until the real trade math starts.

A user may know the stock price, the gain, and the number of shares they want to sell. What they often do not know is the price at which buying back later would actually improve the position after tax, fees, slippage, currency conversion, and their desired extra-share target.

That uncertainty creates a practical problem:

| The user asks | Why it is hard in a normal spreadsheet |
| --- | --- |
| "If I sell now, how low does the stock need to drop before buying back makes sense?" | Taxes, fees, and target share count all move the answer. |
| "What if my cost basis comes from several tax lots?" | Weighted basis math is easy to get wrong and painful to update. |
| "What if I want to track multiple sell scenarios?" | Saved state, live prices, fallback prices, and alert targets drift apart. |
| "Can I trust the number when the market-data API fails?" | Most tools hide failure states or silently reuse stale prices. |
| "Will the app watch prices continuously?" | Local iOS apps cannot honestly promise server-style background monitoring. |

The result is hesitation. Users either overfit a spreadsheet, ignore tax drag, or make the trade with a vague pullback target.

## The Solution

Buyback Calculator turns the sell-and-rebuy decision into a focused, local, transparent workflow.

It starts from the question that matters most:

> At what buy-back price would I recover my post-tax cash, cover costs, account for slippage, and own more shares than before?

The app keeps the calculator as the primary screen, then layers in the tools needed around that decision:

| Need | Product answer |
| --- | --- |
| Fast modeling | A clean calculator built around current price, gain, shares, tax profile, fees, slippage, and target extra shares. |
| Realistic tax basis | Dynamic weighted tax lots with add/delete controls and migration from older fixed-lot inputs. |
| Confidence in the result | A readable calculation trace from proceeds through tax and final maximum buy-back price. |
| Multiple outcomes | Saved scenario comparison with live quote refresh, fallback pricing, alert status, and readiness state. |
| Local honesty | Alerts are local and checked on app price refresh; widgets display alert state but do not claim to trigger notifications. |
| Privacy | Runtime API keys are validated and stored in the shared iOS Keychain access group, not in plaintext defaults. |

## What Users Get

### A clear buy-back limit

The headline number is the maximum price the user can pay to buy back while still hitting the target. It is not just a pullback percentage. It reflects taxes, FX, fees, slippage, and target shares.

### A decision users can audit

The breakdown sheet shows the calculation in plain steps: gross proceeds, sell fees, taxable gain, tax, after-tax cash, buy fees, slippage, target share count, and final buy-back limit.

### Scenario comparison without spreadsheet drift

Users can save scenarios, refresh all prices, compare readiness, and see whether each position is still watching, frozen, or ready to buy back. If live quotes fail, the app falls back to saved prices and says so.

### Tax lots that match real portfolios

Instead of a fixed three-row editor, users can add as many tax lots as needed. The calculation continues to use weighted-average basis, keeping the behavior understandable while allowing more realistic input.

### Alerts with honest behavior

Local alerts can be armed at the calculated buy-back limit or a custom price. They are evaluated when the app refreshes prices, including scenario-dashboard refreshes. The copy makes clear that the app is not running a continuous server-side monitor.

### Pinned assets that stay useful

Users can pin up to 10 saved scenarios as tracked assets for the portfolio widget. The widget shows current or cached prices, recalculates each buy-back limit from the saved tax model, deep links back into the app, and uses fallback prices when live data is unavailable.

## Product Tour

### 1. Select an asset

Search by company name, ticker, ISIN, or WKN. The app uses Finnhub for symbol search and quotes, with OpenFIGI as a best-effort identifier mapping fallback.

### 2. Enter the sell model

Start with price, gain, shares, tax profile, currency, FX, fees, slippage, and target extra shares. Users who know their exact lots can enable tax lots and let the app derive the weighted cost basis.

### 3. Read the result

The main card shows the buy-back limit and required pullback. The detailed breakdown explains how the result was derived, step by step.

### 4. Save and compare scenarios

Saved scenarios preserve the asset, price basis, tax assumptions, FX, fees, slippage, and lots. The comparison dashboard shows symbol, live or fallback price, limit, required drop, tax estimate, after-tax cash, alert target, alert state, and refresh status.

### 5. Freeze after selling

When a user sells, they can freeze the sell price so the buy-back limit remains anchored to the executed trade. Live prices then track whether the current market is at or below the frozen buy-back limit.

### 6. Arm local alerts

Alerts are stored in the shared app group and evaluated locally during app refreshes. Repeated notifications are throttled for six hours per symbol.

### 7. Pin assets to the widget

Pinned assets bring portfolio readiness to the Home Screen. Widget quote refreshes are rate-limit aware, reuse cached prices, and display armed alert targets and status without overstating what a widget can do in the background.

## Calculation Model

The calculator answers one core question: after selling, paying tax and costs, and reserving for slippage, what is the highest buy-back price that still reaches the desired share count?

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

Default assumptions:

| Assumption | Default |
| --- | --- |
| Tax profile | Germany |
| Tax rate | 27% |
| Target extra shares | 2.5% |
| Sell fee | 0 |
| Buy fee | 0 |
| Slippage | 0 |
| FX rate | 1.0 |

Supported tax profiles include Germany, US long-term, US short-term, and Custom. The app includes assumption notes so users can understand what each profile means before relying on the number.

## Local-First Trust Model

Buyback Calculator is designed to be useful even when market data is unavailable.

| Area | Behavior |
| --- | --- |
| User inputs | Stored locally with app storage or app-group storage where sharing with widgets is required. |
| API keys | Validated before use and stored in the shared iOS Keychain access group. |
| Runtime key priority | Shared Keychain key, then bundled build key, then manual or fallback pricing. |
| Market data | Finnhub quotes with OpenFIGI identifier fallback for ISIN/WKN mapping. |
| Quote failures | Surfaced to the user; saved fallback prices remain available. |
| Alerts | Local notifications only, evaluated when app refreshes prices. |
| Widgets | Display calculations, fallback status, frozen states, and armed alert targets. |
| Backend | No backend or server-push alert service in this release. |

This keeps the app honest: it improves the user's decision without pretending to provide continuous server-side monitoring.

## Feature Map

| Feature | User value |
| --- | --- |
| Liquid Glass SwiftUI interface | A focused iOS 26+ experience with clean cards, native glass controls, and polished navigation chrome. |
| Locale-aware numeric parsing | Users can paste values with currency symbols, grouping separators, spaces, comma decimals, or dot decimals. |
| Dynamic tax lots | More realistic portfolio modeling without forcing users into a fixed three-row structure. |
| Calculation trace | Every major number can be inspected from proceeds to final buy-back limit. |
| Scenario comparison | Users can compare multiple saved decisions instead of rebuilding them manually. |
| Refresh All | Saved scenarios can refresh market prices together while keeping fallback clarity. |
| Freeze workflow | Executed sell prices stay fixed while live quotes track buy-back readiness. |
| Local alerts | Practical local reminders that are explicit about refresh-based evaluation. |
| Pinned-asset widgets | Users can pin up to 10 assets; widgets track current or cached prices and recalculate buy-back limits from saved scenario inputs. |
| API-key management | Runtime keys are accepted, validated, stored securely, and shared with the widget through Keychain entitlements. |

## Market Data And API Keys

The app can run entirely with manual prices, but live data improves the workflow.

Providers:

- Finnhub: symbol autocomplete and quotes
- OpenFIGI: optional ISIN and WKN mapping fallback

Users can add keys in app settings. App-entered keys are validated and stored in the shared iOS Keychain access group so the app and widget can use the same runtime credentials.

For local development with bundled keys, create a private config file:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Then add:

```text
FINNHUB_API_KEY = your_finnhub_key
OPENFIGI_API_KEY = your_openfigi_key_optional
```

`Config/Secrets.xcconfig` is ignored by git. If no Finnhub key is available, the app and widget continue to work with manual or saved fallback prices.

## Developer Setup

The Xcode project is generated from `project.yml`.

Targets:

| Target | Purpose |
| --- | --- |
| `BuybackCalculator` | Main iOS app |
| `BuybackWidgetExtension` | WidgetKit extension |
| `BuybackCalculatorTests` | Unit tests for calculation, storage, parsing, alerts, keys, and shared scenario logic |

Regenerate the project after changing target membership, build settings, entitlements, or Info.plist properties:

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

## Widget Usage

Single-stock calculator widget:

1. Build and install the app.
2. Add the `Buy-Back Calculator` widget to the Home Screen.
3. Long-press the widget and choose `Edit Widget`.
4. Enter symbol, gain, fallback price, and optional tax or fee settings.
5. Tap the widget to open the matching app calculation.

Portfolio widget:

1. Save scenarios in the app.
2. Pin up to 10 saved scenarios from the result actions or scenario comparison sheet.
3. Add the `Buy-Back Portfolio` widget.
4. Use live or cached quote refresh where available and fallback prices where needed.
5. Freeze a row after selling to keep the executed sell price fixed.
6. Open the app to edit the frozen sell price to the exact broker fill.

Pinned quote refresh is intentionally local and rate-limit aware. The app and widget share saved scenarios, alerts, API-key availability, and quote cache through the app group; every app-side scenario, pin, alert, key, freeze, and quote update bumps a shared widget sync revision and requests an immediate WidgetKit timeline reload. iOS can still coalesce the actual repaint, while scheduled widget timelines continue roughly every 15 minutes and each asset quote is reused for at least five minutes.

## Roadmap

Server-side alerts are intentionally out of scope for this local-first release. The future backend path is documented in [`docs/ROADMAP.md`](docs/ROADMAP.md), including APNs registration, quote polling, provider fallback, alert rules, privacy, API-key handling, and migration from local-only alerts.

## Important Note

Buyback Calculator is a planning tool, not financial, investment, or tax advice. Tax rules vary by jurisdiction and user situation. Users should verify assumptions against their broker statements, tax reports, and professional guidance before trading.
