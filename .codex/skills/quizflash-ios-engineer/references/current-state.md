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
- Source now uses `deepseek-flash`, a versioned immutable D1 pricing catalog with an atomic active-version pointer, peak/off-peak response-model accounting, and a 1,500,000 microUSD rolling 30-day internal Premium default. The active generation may finish with a small overshoot; the next generation is rejected. Accounting failures block new starts instead of silently recording zero cost.
- iOS shows Premium AI usage as a percentage plus renewal timing and maps quota exhaustion to localized English/Romanian/Russian copy without exposing internal USD values. The exact retired 2,000,000 default is migrated lazily on the next canonical Firestore account read; custom limits remain unchanged.
- D1 migration `0006` and the Worker release are live. `/health` reports `deepseek-flash@2026-09-10`, model `deepseek-flash`, the 1,500,000 microUSD default, and a 2026-10-10 pricing review date. A real 100-card sandbox request completed with 96 validated cards and cost 48,211 microUSD in the `off_peak` band; all 26 provider calls were recorded as `accounted` with the active pricing version, and the rolling quota advanced from 4,213 to 52,424 microUSD.

## Subscriptions And Store Rollout

- RevenueCat Purchases SDK is integrated in iOS. `SubscriptionManager` configures it after Firebase Auth with Firebase UID as `appUserID`, loads the monthly package, purchases, restores, and refreshes backend-authoritative state.
- The Worker has signed RevenueCat webhook ingestion, idempotent retry storage, REST reconciliation, and Firestore subscription projection. Remote RevenueCat secrets and webhook configuration still require rollout verification before production sales.
- The repository currently carries a RevenueCat Test Store public SDK key. Replace it with the Apple app public SDK key only after the RevenueCat Apple configuration and product mappings validate.
- App Store Connect contains the iOS app `QuizFlash AI` with bundle ID `com.sion.QuizFlash`, subscription group `QuizFlash Premium`, and monthly product `com.sion.QuizFlash.premium.monthly` with one-month duration and worldwide availability.
- QuizFlash intentionally launches with only the monthly subscription; annual UI, source configuration, tests, and rollout documentation have been removed. The App Store monthly product has worldwide availability and English, Romanian, and Russian customer metadata. Its remaining work is price confirmation, review information, and RevenueCat product/entitlement/offering mapping. The measured AI cost supports the 5.99 USD/month launch price with the 1.50 USD rolling internal AI budget.
- The App Store Connect API credential validates in RevenueCat. The In-App Purchase key currently needs attention until Apple/RevenueCat recognizes it as compatible with the newly created app record.
- Paid-app and tax agreements are active. Banking processing and trader phone verification remain external launch blockers to recheck rather than solve in source code.

## Immediate Work Order

1. Confirm the monthly App Store price and complete its review information.
2. Import/map the monthly product to the RevenueCat `premium` entitlement and default offering.
3. Switch to the production Apple RevenueCat public SDK key and run sandbox purchase, restore, renewal/cancellation, webhook, Firestore, relaunch, and second-device verification.
