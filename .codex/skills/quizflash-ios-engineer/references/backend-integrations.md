# Backend Integrations

Read this reference before changing Firebase, cloud AI, quotas, provider credentials, paywalls, purchases, RevenueCat, or Firestore rules.

## Current State

- Firebase project: the configured default project in `.firebaserc` is `cgram-1f28a`.
- The iOS app boots Firebase in `App/QuizFlashApp.swift` and uses Firebase Auth, Firestore, and Firebase Functions.
- Firestore is the current live backend for Auth-linked profiles, cloud deck sync, manual premium state, and the Spark-compatible free AI quota fallback.
- `functions/src/index.ts` contains Cloud Functions for profile upsert, AI quota consumption, DeepSeek generation, and account-data deletion. Cloud Functions deployment requires the Firebase Blaze plan; do not report a local source change as deployed until deployment succeeds.
- `CloudAIGenerationService` exists but the editor currently uses the configurable direct `AIFlashcardService` path. A project-owned DeepSeek key must not remain in a shipped client path.
- RevenueCat is not integrated yet. `SubscriptionManager` currently reads Firebase custom claims and the user document; `restorePurchases()` is intentionally a placeholder.

## Authority And Identity

1. Use the Firebase Auth UID as the only durable user key across Firestore, Functions, and RevenueCat `appUserID`.
2. Treat the backend as authoritative for plan, entitlement, quota, card limit, AI spend, and provider credentials. The client may display a cached value and preflight a request, but it must not be the final allow/deny decision.
3. Keep local SwiftData data separate from cloud documents and AI DTOs. Continue using the shared deck JSON/card DTO boundary.
4. Never use email as a document key or entitlement key. Email may change and is personal data.
5. Never put a Firebase Admin credential, DeepSeek project key, RevenueCat secret key, webhook secret, receipt, or CLI token in the app, repository, Firestore, logs, diagnostics, screenshots, or messages.

## Firestore Contract

### User Document

`users/{uid}` is the user-owned profile plus server-owned access state.

- Client-owned profile fields: `email`, `displayName`, `photoURL`, `providers`, and safe presentation metadata.
- Server-owned or admin-owned fields: `plan`, `premium`, `usage`, `cost`, `freeGenerationsUsed`, `freeGenerationsLimit`, and `initialMigrationCompleted`.
- Current rules permit a signed-in user to create/update their own safe profile fields. They permit exactly one narrow fallback mutation for a free generation: increment `freeGenerationsUsed` by one while preserving the current limit and only changing that counter plus `updatedAt`.
- Do not make `plan` or `premium` client-writable. Do not broaden the fallback rule into a general usage write.
- Cloud deck data remains below `users/{uid}/decks/{deckId}/cards/{cardId}`. The current design uses soft deletion because client deletes are denied by the rules; account cleanup is a callable backend operation.

Whenever the document shape changes, update all of these together: the iOS writer/reader, `firestore.rules`, Functions, migration/defaulting logic, and tests or emulator coverage.

## AI Quota And Card Limits

The current product contract is fixed:

| Plan | Lifetime free generations | Maximum cards per generation |
| --- | ---: | ---: |
| Free | 5 | 30 |
| Premium | N/A | 100 |

Keep one source of truth for these values per authority boundary. Today they appear in `SubscriptionManager` and `functions/src/index.ts`; change them together or move them to a shared backend-delivered configuration before adding more tiers.

Required behavior:

1. Refresh plan state before presenting or confirming AI generation so a manual/admin entitlement change updates the picker promptly.
2. Validate `targetCards` in the UI for clear feedback, then validate it again in the Firestore transaction or Callable Function. Never trust the picker clamp.
3. Read `premium`/`plan` inside the same transaction or trusted server request that consumes quota. Do not authorize from stale client memory.
4. Update the UI from the authoritative response or Firestore listener after a successful mutation.
5. Make retries idempotent. A network retry must not consume two generations or create two paid requests. Add an idempotency key/request document before enabling the cloud generation path for users.
6. Do not charge a free generation for a failed provider request. The current Spark fallback consumes before direct generation; treat that as a known temporary limitation. The production callable generation path should reserve, call the provider, then atomically finalize usage only after a valid response, with recovery for interrupted reservations.
7. Test at least free request 1, free request 5, rejected request 6, free 31-card rejection, premium 100-card acceptance, premium 101-card rejection, plan changes while the app is open, and two concurrent requests.

## DeepSeek Production Boundary

Use DeepSeek only from a trusted backend once Cloud Functions are deployable:

1. Store `DEEPSEEK_API_KEY` as a Firebase Functions secret. Use configuration parameters only for non-secret values such as base URL, model, and a budget ceiling.
2. Keep the current Functions request schema narrow: authenticated UID, validated source, validated `targetCards`, and validated generation options. Do not forward arbitrary client headers, models, prompts, pricing, or provider configuration.
3. Enforce per-plan card limits, quota, per-user concurrency, request size, source-text size, monthly cost, and provider retry policy in the callable function. Handle provider `429`/`Retry-After` explicitly and return a stable app error.
4. Record non-sensitive operational fields in a server-owned usage document: request ID, time, model, input/output token counts when returned, generated-card count, calculated cost, status, and failure class. Never store API keys or full user source text merely for telemetry.
5. Calculate cost from the actual model/token pricing used by the deployed model. The current `costCents` increment of `0` is scaffolding, not a real budget enforcement implementation.
6. Validate DeepSeek JSON against the shared deck/card DTO before persistence. Reject malformed, oversized, or unexpected output; never write provider output directly into SwiftData or Firestore without validation.
7. Keep `AIProviderStore` only for developer-selected personal keys or debug testing. It persists provider profiles locally and is not an acceptable storage location for the app's production key. Gate or remove that path in release builds before a public launch.
8. Enable App Check and set callable functions to enforce it before production rollout, after verifying the iOS App Check provider and test devices. Do not silently turn App Check off to bypass a configuration issue.

## Firebase Operations

1. Use `npx --yes firebase-tools` from the repository root and the configured project. Never paste a Firebase login token into files or commands committed to git.
2. Inspect `firebase.json`, `.firebaserc`, `firestore.rules`, and `functions/` before a deploy. Build Functions with `npm run build` (or `npm run lint`) in `functions/`.
3. Test new rules with the Emulator Suite or rules tests before deployment. A successful iOS build does not validate Firestore authorization.
4. Deploy rules and Functions as separate deliberate actions. The Spark plan can deploy rules but blocks Cloud Functions; record this blocker precisely instead of pretending the callable path is live.
5. Preserve a rollback path: know the prior rules/function revision, deploy a narrow change, and verify an authenticated user cannot read/write another UID or protected access fields.

## RevenueCat Rollout

Do not add a paywall first. Build entitlement synchronization first, then the purchase UI.

1. Wait for Apple Developer and App Store Connect access. Create the app record, subscription products, subscription group, sandbox tester, and required agreements/tax/banking configuration.
2. Add RevenueCat iOS SDK through Swift Package Manager. Configure it only after Firebase Auth resolves, using the Firebase UID as `appUserID`. Log out or reidentify RevenueCat when the Firebase session changes; never leave the previous user's entitlement cached on the next user.
3. Define one entitlement identifier, for example `premium`. Map App Store products/offering packages to that entitlement in RevenueCat.
4. Make RevenueCat's signed webhook/backend integration update Firebase through Admin SDK: write the server-owned plan fields and, if used, Firebase custom claims. Verify webhook signature and process events idempotently by event ID.
5. Keep Firestore as the app's common entitlement read model. `SubscriptionManager` should refresh the user document and forced Firebase ID token after a purchase, restore, renewal, cancellation, refund, or webhook update. Do not let a device write `premium: true`.
6. Let the client display RevenueCat entitlement state for responsiveness, but let Firestore/Functions decide backend access. Handle delayed webhooks with a bounded refresh/pending state rather than granting permanent access from an unverified local flag.
7. Replace the placeholder `restorePurchases()` with the RevenueCat restore flow, then refresh Firebase state and validate the user can use the entitlement after an app restart and on a second device.
8. Migrate current manual premium documents deliberately: define who is eligible, set server-owned fields once, track migration version, and remove temporary manual-admin UI before launch.

## Required Verification

For a backend or billing change, verify all applicable layers:

1. `npm run build` in `functions/` and the targeted iOS `xcodebuild` destination.
2. Firestore rules behavior for owner/non-owner and protected fields.
3. Fresh account, free-limit boundary, premium boundary, entitlement downgrade, sign-out/sign-in, and app relaunch.
4. Function error mapping for unauthenticated, invalid target count, quota exhausted, provider rate limit, provider malformed JSON, and timeout.
5. RevenueCat sandbox purchase, restore, renewal/cancellation simulation, webhook delivery, Firebase document/claim update, and cross-device refresh.

Report what ran, what reached Firebase, and every remaining deployment or platform blocker. Do not say an integration is complete while it remains source-only or a required remote configuration is missing.
