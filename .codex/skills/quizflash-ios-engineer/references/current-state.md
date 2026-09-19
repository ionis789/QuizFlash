# QuizFlash Current State

Last refreshed: 2026-09-19.

Read this file at the start of every QuizFlash task. It is a living snapshot, not a changelog. When a material implementation or external rollout state changes, replace or remove the stale statement in the same task; do not append historical notes.

## Product And Runtime

- QuizFlash is a pre-release iOS 17+ Swift 6 app built with SwiftUI, SwiftData, Firebase, Cloudflare Workers, DeepSeek, and RevenueCat.
- The supported app languages are English, Romanian, and Russian. App-owned copy must stay synchronized across all three localizations and `Docs/UI-Dictionary/localization_matrix.tsv`.
- The supported card types are flashcards and quizzes. Home is a study dashboard; the removed exam-goals product area must not be restored implicitly.

## Backend And AI

- Firebase Auth UID is the durable identity across Firestore, the Cloudflare Worker, and RevenueCat.
- Firestore is authoritative for entitlement, AI quota, rolling billing anchor, usage, and account state. The iOS client may display cached state but cannot grant Premium or mutate protected usage fields.
- Production AI runs through the deployed `quizflash-ai` Cloudflare Worker and its D1/Durable Object infrastructure. Firebase Cloud Functions remain source-only and are not the live DeepSeek path.
- The Worker already provides authenticated generation sessions, raw DeepSeek proxying, per-call token telemetry, idempotent retry caching, rolling 30-day usage finalization, account deletion, prompt configuration, and RevenueCat reconciliation/webhook handling.
- Current source still uses the retired `deepseek-v4-flash` alias, June 2026 flat accounting rates, and a 2,000,000 microUSD Premium default. These values are known stale and must not be described as the desired final contract.
- The next approved backend change is a versioned D1 pricing catalog for `deepseek-flash`/DeepSeek V4.1 Flash, peak/off-peak accounting, and a 1,500,000 microUSD rolling 30-day internal Premium limit. The active generation may finish with a small overshoot; the next generation is rejected. The UI will show percentage and reset timing, not internal USD cost. This plan is not implemented yet.

## Subscriptions And Store Rollout

- RevenueCat Purchases SDK is integrated in iOS. `SubscriptionManager` configures it after Firebase Auth with Firebase UID as `appUserID`, loads monthly/annual packages, purchases, restores, and refreshes backend-authoritative state.
- The Worker has signed RevenueCat webhook ingestion, idempotent retry storage, REST reconciliation, and Firestore subscription projection. Remote RevenueCat secrets and webhook configuration still require rollout verification before production sales.
- The repository currently carries a RevenueCat Test Store public SDK key. Replace it with the Apple app public SDK key only after the RevenueCat Apple configuration and product mappings validate.
- App Store Connect contains the iOS app `QuizFlash AI` with bundle ID `com.sion.QuizFlash`, subscription group `QuizFlash Premium`, and monthly product `com.sion.QuizFlash.premium.monthly` with one-month duration and worldwide availability.
- The monthly subscription still needs its price, customer-facing localization, review metadata, and RevenueCat product/entitlement/offering mapping. The annual product has not been created. The working launch price recommendation is 5.99 USD/month, to be confirmed after the accounting change is measured.
- The App Store Connect API credential validates in RevenueCat. The In-App Purchase key currently needs attention until Apple/RevenueCat recognizes it as compatible with the newly created app record.
- Paid-app and tax agreements are active. Banking processing and trader phone verification remain external launch blockers to recheck rather than solve in source code.

## Immediate Work Order

1. Implement and deploy the approved DeepSeek accounting/budget change, then verify one real large generation and its recorded cost.
2. Complete the monthly App Store subscription metadata and price.
3. Create the annual subscription, then import/map both products to the RevenueCat `premium` entitlement and default offering.
4. Switch to the production Apple RevenueCat public SDK key and run sandbox purchase, restore, renewal/cancellation, webhook, Firestore, relaunch, and second-device verification.
