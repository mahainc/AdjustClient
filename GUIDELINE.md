# AdjustClient — Integration Guideline

A TCA-style dependency wrapper around the [Adjust iOS SDK v5](https://github.com/adjust/ios_sdk).
Exposes a small, async, Sendable surface so feature reducers can track installs, events,
revenue, and deep links without importing `AdjustSdk` directly.

---

## 1. What Adjust does

Adjust is a **mobile measurement partner (MMP)**. On first launch its SDK collects a
small device fingerprint (IDFA when ATT-authorised, IDFV, IP, user-agent) and posts it to
Adjust's backend. The backend matches the install against recent ad clicks and replies with
an **attribution** payload — which network / campaign / adgroup / creative drove the install.
After that the SDK keeps tracking sessions, custom events, ad revenue, IAP / subscription
revenue, and deep-link clicks for as long as the app is installed.

The four feature areas you'll touch through this wrapper:

| Area | Purpose |
|---|---|
| **Sessions** | Auto-tracked once `initialize()` runs. No manual API. |
| **Events** | Custom conversions, fired with `trackEvent(token, params)`. |
| **Revenue** | Three flavours — ad revenue, subscriptions, verified IAPs. |
| **Deep links** | Three flavours — direct (warm), deferred (cold install), resolved (short link). |

---

## 2. Lifecycle

```
App launch
   │
   ▼
[Host app prompts ATT]   ◄── not wrapped — see §4
   │
   ▼
adjustClient.initialize(config)
   │
   ▼
Adjust.initSdk → first session sent → attribution callback (within a few seconds in sandbox)
   │
   ▼
[ongoing] trackEvent / trackRevenue / trackSubscription / processDeeplink
   │
   ▼
attributionStream() emits → fan into AnalyticClient (see §7)
```

All `track*` and `process*` calls made **before** `initialize()` are queued by an internal
actor (`AdjustState.perform` in `Live.swift`) and drained in insertion order once `Adjust.initSdk`
returns. You can safely wire feature reducers that call `trackEvent` from a child screen even
before the app's `init()` has finished.

If `initialize()` is called with an empty `appToken`, the SDK is **not** initialised and any
queued calls are dropped (with a `#if DEBUG` warning). Completion-bearing endpoints
(`resolveDeeplink`, `isEnabled`, `verifyAndTrackPurchase`) resume their continuations with a
sentinel value rather than hanging — so it's safe to call them from a Live preview where the
SDK was never started.

---

## 3. Initialization

```swift
@Dependency(\.adjustClient) var adjustClient

await adjustClient.initialize(.init(
    appToken: "abc123def456",                     // 12-char token from Adjust dashboard
    environment: .sandbox,                        // .sandbox for dev, .production for App Store
    logLevel: .info,                              // .verbose / .debug / .info / .warn / .error / .suppress
    revenueEventToken: "rev_token"                // optional — see §6
))
```

**Order matters**:
- The wrapper installs its delegate bridge **before** calling `Adjust.initSdk`. The Adjust
  SDK retains the delegate weakly, so the bridge is a process-wide singleton
  (`AdjustDelegateBridge.shared`) to keep it alive.
- Call `initialize(_:)` exactly once per process. Re-initialising is a no-op.
- Sandbox builds should always use `.sandbox` — production data won't appear in the
  testing dashboard otherwise.

---

## 4. ATT (App Tracking Transparency) — host app's responsibility

This wrapper **does not call `ATTrackingManager.requestTrackingAuthorization`**. The host app
owns ATT for two reasons: (a) the prompt copy and timing belong in the UI layer, and (b) other
SDKs (AdMob, analytics) need the same authorisation, so it's owned once globally.

Recommended flow:

```swift
import AppTrackingTransparency

// In your @main App.init or first-launch coordinator:
let status = await ATTrackingManager.requestTrackingAuthorization()
await adjustClient.initialize(config)   // initialize AFTER the user's decision
```

If you prompt **after** `initialize()`, Adjust will still pick up IDFA on the next session,
but the *first* session (and therefore the install attribution) will go out without IDFA —
which materially hurts attribution accuracy on iOS 14+. Always prompt first.

---

## 5. Deep links — three flavours

| Type | Trigger | Wrapper API |
|---|---|---|
| **Direct (warm)** | App is installed; user taps an Adjust campaign URL → OS hands it via `UIScene.openURLContexts` | `await adjustClient.processDeeplink(url, referrer: nil)` |
| **Deferred (cold install)** | User clicks a deep-link ad **before** installing → Adjust posts the URL back on first launch | Subscribe to `adjustClient.deeplinkStream()` |
| **Resolved (short link)** | An Adjust short URL needs to be unwrapped to its final destination | `let final = await adjustClient.resolveDeeplink(url, referrer: nil)` |

For direct deep links, always pass through Adjust *before* routing — Adjust extracts the
campaign params and registers the click. The deferred-deeplink callback in
`AdjustDelegateBridge.adjustDeferredDeeplinkReceived(_:)` returns `false` so the **app** —
not Adjust — owns routing; subscribers to `deeplinkStream()` get the URL and route to the
right feature themselves.

```swift
// SceneDelegate / @main App URL handler
func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    for ctx in contexts {
        Task { await adjustClient.processDeeplink(ctx.url, referrer: nil) }
        router.handle(ctx.url)   // app routes regardless of Adjust
    }
}

// Somewhere stable — e.g. a long-lived Task in the root reducer
for await url in adjustClient.deeplinkStream() {
    router.handle(url)
}
```

---

## 6. Revenue — three flavours

### 6a. Ad revenue (AdMob mediation)

```swift
await adjustClient.trackRevenue(.init(
    amount: 0.0123,
    currency: "USD",
    adUnit: "interstitial_home"
))
```

`Revenue` defaults `network = "AdMob"`, `source = "admob_sdk"`, `placement = "default"`,
`impressions = 1`. Override per-network when you mediate via AppLovin / IronSource etc.

If you also set `Config.revenueEventToken`, the wrapper will additionally fire a regular
event with the same revenue/currency. Use this only when your dashboard has a custom event
configured to mirror ad revenue (some dashboards expect that for legacy reasons).

### 6b. Subscriptions (auto-renewables / first purchase)

```swift
await adjustClient.trackSubscription(.init(
    price: Decimal(string: "9.99")!,
    currency: "USD",
    transactionId: storeKitTransaction.id,
    transactionDate: storeKitTransaction.purchaseDate,
    salesRegion: storefrontCountryCode      // "US", "DE", etc.
))
```

Adjust dedupes by `transactionId` server-side, so it's safe to call this on every renewal
event from `Transaction.updates`.

### 6c. Receipt-validated IAPs

```swift
let result = await adjustClient.verifyAndTrackPurchase(
    "purchase_event_token",
    .init(productId: "premium.monthly", transactionId: storeKitTransaction.id),
    Revenue(amount: 9.99, currency: "USD", adUnit: "iap")   // optional revenue payload
)

switch result.status {
case .success:     // Adjust verified the receipt + tracked the event
case .failure:     // backend says receipt is invalid (fraud / refund)
case .notVerified: // SDK or network couldn't reach backend (treat as retry)
case .unknown:     // backend gave a status we don't recognise
}
```

Use this for any IAP you'd otherwise track with `trackEvent` — receipt validation closes
the fraud loop on jailbroken / patched StoreKit traffic.

---

## 7. Attribution → analytics fan-out

Subscribe **once**, at app start, to `attributionStream()` and fan-out to your analytics
client. The stream is multicast; multiple subscribers are fine but unnecessary.

```swift
Task {
    for await attr in adjustClient.attributionStream() {
        if let network = attr.network {
            await analyticClient.setUserProperty("acquisition_network", network)
        }
        if let campaign = attr.campaign {
            await analyticClient.setUserProperty("acquisition_campaign", campaign)
        }
        if let adgroup = attr.adgroup {
            await analyticClient.setUserProperty("acquisition_adgroup", adgroup)
        }
    }
}
```

`Attribution` mirrors `ADJAttribution` 1-to-1 (all fields nullable). The first emission
typically arrives within ~5 seconds in sandbox, ~30–60 seconds in production. The stream
re-emits on every attribution change (rare — re-engagement campaigns).

---

## 8. Privacy / consent

| API | Effect | Reversible? |
|---|---|---|
| `setEnabled(false)` | Pauses sessions / events / revenue. State persists across launches. | Yes — `setEnabled(true)` resumes. |
| `isEnabled() async -> Bool` | Reads the kill-switch state. | n/a |
| `gdprForgetMe()` | Stops tracking and deletes user's data on Adjust backend. | **No.** One-way. |
| `setThirdPartySharing(.init(isEnabled: false))` | Opts user out of CCPA-class third-party data sharing. | Yes — pass `isEnabled: true` (or partner-granular settings) to opt back in. |
| `setMeasurementConsent(true)` | Marks user as having opted in to measurement (for GDPR pipelines that require explicit consent). | Yes — pass `false` to revoke. |

**Do not** call `gdprForgetMe()` casually; once invoked, the user can never be re-tracked
on this device install.

For granular per-partner sharing (e.g. opt out of Snapchat but allow Facebook):

```swift
await adjustClient.setThirdPartySharing(.init(
    isEnabled: nil,   // server decides default
    granularOptions: ["facebook": ["consent": "granted"]],
    partnerSharingSettings: ["snapchat": ["everything": false]]
))
```

---

## 9. Best practices

- **Initialize once**, in `@main App.init()` or `application(_:didFinishLaunchingWithOptions:)`,
  **after** the ATT decision.
- **Subscribe to `attributionStream()` and `deeplinkStream()` once** at app start. Both are
  multicast — extra subscribers waste cycles for no gain.
- **Don't re-initialize.** A second `initialize()` call is silently ignored.
- **Use `.sandbox` for dev / TestFlight, `.production` for App Store.** Sandbox events appear
  in the Adjust dashboard's "Testing console" only.
- **Tests should use `AdjustClient.noop`** (or per-test custom stubs) — never the live client.
  The `@DependencyClient` macro auto-generates a `testValue` that crashes on call, so
  `withDependencies { $0.adjustClient = .noop }` is the test-time pattern.
- **Validate `appToken` upstream.** An empty token is treated as "skip init" (with a debug
  log) — fine for previews, but you want a build-time check or a release-config assertion
  for production.

---

## 10. Known limitations of this wrapper

The wrapper is intentionally narrow. The following SDK features are **not** exposed; reach
into `AdjustSdk` directly (or extend the wrapper) if you need them:

- **ATT** (`requestAppTrackingAuthorization`) — host app owns it; see §4.
- **SKAdNetwork conversion-value updates** (`updateSkanConversionValue`) — Adjust manages
  CV automatically based on dashboard config. Only needed for fully custom CV mappings.
- **Global callback / partner parameters** (`addGlobalCallbackParameter` etc.) — useful if
  you want every event tagged with `userId`; not currently wrapped.
- **Remote triggers** (`adjustRemoteTriggerReceived`, v5.6+) — backend-pushed triggers.
- **First-session delay** (`enableFirstSessionDelay` / `endFirstSessionDelay`) — for apps
  that need to delay the first session until consent is captured.
- **COPPA mode** (`enableCoppaCompliance`) — for child-directed apps.
- **Store info** (`ADJStoreInfo`) — for non-App-Store distributions (Galaxy Store etc.).
- **Offline mode** (`switchToOfflineMode`) — niche; mostly used for E2E test rigs.
- **ID getters** (`idfa`, `idfv`, `adid`, `lastDeeplink`) — usually not needed in feature
  code; if you want `adid` for analytics, read it once after the first attribution emission.

If you need any of the above, extend `Interface.swift` + `Live.swift` following the same
pattern: a Sendable value type in `Models.swift`, an `async` endpoint on the
`@DependencyClient` struct, a stub in `Mocks.swift`, and the live mapping behind
`state.perform { ... }`.
