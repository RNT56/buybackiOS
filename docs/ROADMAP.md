# Roadmap

## Backend Price Alerts

This release keeps price alerts and freeze tracking local. Frozen saved positions store the sell price on device, and widgets can update that local state, but widgets do not trigger notifications.

Alerts are evaluated when prices refresh in the app or scenario dashboard; frozen scenarios compare refreshed live prices against the frozen buy-back limit. Widgets may show saved alert targets and ready states, but they do not monitor prices continuously.

Future server-push alerts should be implemented as a separate backend-backed release:

- Register devices for APNs from the app and store only the minimum token, symbol, target price, currency, and user-facing scenario metadata needed to deliver alerts.
- Poll market data server-side on a controlled schedule with provider fallback, rate-limit handling, stale-quote detection, and alert throttling.
- Keep user API keys out of the backend unless there is an explicit account/security model; prefer backend-owned provider credentials.
- Support migration from local alerts by offering an opt-in sync step that uploads currently enabled local alerts.
- Preserve the local alert mode as a fallback when push registration, network access, or backend service health is unavailable.
- Add monitoring for quote freshness, polling failures, provider limits, APNs delivery failures, and alert trigger volume.
