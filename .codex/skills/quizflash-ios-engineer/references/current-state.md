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
- The Worker has signed RevenueCat webhook ingestion, idempotent retry storage, REST reconciliation, and Firestore subscription projection. Its RevenueCat V1 secret API key and explicit sandbox Firebase UID allowlist are deployed. Server reconciliation deliberately omits the client-only `X-Platform` header; RevenueCat previously rejected that secret-key/header combination with HTTP 403. Webhook credentials and delivery still require rollout verification before production sales.
- RevenueCat keys are configuration-specific: Debug uses the Test Store public SDK key so development can continue while Apple account setup is pending, and Release uses the QuizFlash Apple app public SDK key. Secret API and webhook credentials remain server-only.
- App Store Connect contains the iOS app `QuizFlash AI` with bundle ID `com.sion.QuizFlash`, subscription group `QuizFlash Premium`, and monthly product `com.sion.QuizFlash.premium.monthly` with one-month duration and worldwide availability.
- QuizFlash intentionally launches with only the monthly subscription; annual UI, source configuration, tests, rollout documentation, and obsolete annual RevenueCat configuration have been removed. The App Store monthly product has worldwide availability, a 5.99 USD/month reference price with Apple's regional equivalents, and English, Romanian, and Russian customer metadata. RevenueCat maps both the development Test Store monthly product and `com.sion.QuizFlash.premium.monthly` to the `premium` entitlement and the `default` offering's `$rc_monthly` package. Its remaining store work is review information. The measured AI cost supports this launch price with the 1.50 USD rolling internal AI budget.
- The App Store Connect API credential validates in RevenueCat. Debug/Test Store now loads the monthly package and localized 9.99 USD test price on a physical device; purchase reached backend reconciliation, exposing and fixing the secret-key `X-Platform` 403. End-to-end restore and entitlement projection still need confirmation. A physical-device check with the Apple RevenueCat SDK key previously reached RevenueCat but StoreKit returned no App Store product; complete the subscription review screenshot, wait for banking to finish processing, recheck the In-App Purchase key, then allow Apple sandbox propagation before retrying the Release path.
- The app is not ready for App Review yet; UI work and App Store marketing screenshots remain. The Paid Apps Agreement is `Pending User Info`, the Moldova bank account is still `Processing` inside Apple's stated 24-hour window, the W-8BEN is active but the separate U.S. Certificate of Foreign Status still shows missing tax information, and the EU DSA trader phone verification SMS has not arrived. These are external account blockers, not source-code failures.

## Immediate Work Order

1. Finish the remaining application UI work; do not submit the app or subscription for review yet.
2. Clear the Apple business blockers: finish required tax information, let banking finish processing, and complete or manually verify the EU trader phone number.
3. Complete the monthly subscription review information and confirm its localized App Store price loads on a physical device.
4. Finish the in-progress Test Store restore/reconciliation check, then configure and verify the remote RevenueCat webhook credentials and delivery.
5. Run renewal/cancellation, Firestore projection, relaunch, Release Apple sandbox, and second-device verification.
