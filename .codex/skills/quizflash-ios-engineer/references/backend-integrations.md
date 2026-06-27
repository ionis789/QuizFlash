# Backend Integrations

Read this reference before changing Firebase, cloud AI, quotas, provider credentials, paywalls, purchases, RevenueCat, or Firestore rules.

## Current State

- Firebase project: the configured default project in `.firebaserc` is `quizflash-6b0ea`.
- The iOS app boots Firebase in `App/QuizFlashApp.swift` and uses Firebase Auth, Firestore, and Firebase Functions.
- Firestore rules are deployed to the fresh `quizflash-6b0ea` project. The project has no legacy user or deck data and must not acquire a first-login migration path.
- Firestore is the canonical backend for Auth-linked profiles, background deck sync, manual premium state, free AI quota, and monthly AI usage.
- Firebase Cloud Functions remain source-only because the project does not use Firebase Blaze. They are not the production DeepSeek path.
- Production AI uses the Cloudflare Worker described in `references/ai-proxy.md`. Release builds use its transparent proxy; DEBUG may use a developer-selected direct provider profile. A project-owned DeepSeek key must never remain in a shipped client path.
- RevenueCat is not integrated yet. `SubscriptionManager` currently reads Firebase custom claims and the user document; `restorePurchases()` is intentionally a placeholder.

## Authority And Identity

1. Use the Firebase Auth UID as the only durable user key across Firestore, Functions, and RevenueCat `appUserID`.
2. Treat the backend as authoritative for plan, entitlement, quota, card limit, AI spend, and provider credentials. The client may display a cached value and preflight a request, but it must not be the final allow/deny decision.
3. Keep local SwiftData data separate from cloud documents and AI DTOs. Continue using the shared deck JSON/card DTO boundary.
4. Never use email as a document key or entitlement key. Email may change and is personal data.
5. Never put a Firebase Admin credential, DeepSeek project key, RevenueCat secret key, webhook secret, receipt, or CLI token in the app, repository, Firestore, logs, diagnostics, screenshots, or messages.

## Deck Sync Contract

1. The app is authenticated before the user can create or edit decks. A newly saved deck and every newly saved card must be assigned the active Firebase UID plus a stable cloud ID before it is queued for upload.
2. Do not upload old local decks on sign-in. There is no `initialMigrationCompleted`, no backfill, and no legacy-data migration in this project.
3. SwiftData remains the immediate local store. Queue cloud upload after the local save succeeds; persist the outbox and retry after a network error or app relaunch without blocking the editor or showing a manual Sync control.
4. On login, subscribe to `users/{uid}/decks` and download only that UID's data. Do not read another user path, reuse the previous user's listener, or merge content across UIDs.
5. Resolve simultaneous edits with `editedAt`: the later value wins. Decks and cards are soft-deleted in Firestore, and a client must not use direct Firestore deletes.

## Firestore Contract

### User Document

`users/{uid}` is the user-owned profile plus server-owned access state.

- Client-owned profile fields: `email`, `displayName`, `photoURL`, `providers`, and safe presentation metadata.
- Server-owned or admin-owned fields: `plan`, `premium`, `usage`, `cost`, `freeGenerationsUsed`, and `freeGenerationsLimit`.
- Current rules permit a signed-in user to create/update only their own safe profile fields. Quota and usage fields are server/admin-owned; the iOS client cannot initialize, increment, or reset them.
- Do not make `plan`, `premium`, quota, or usage client-writable.
- Monthly canonical usage is stored at `users/{uid}/usage/{YYYYMM}`. Finalized generation IDs are stored as server-only idempotency records at `users/{uid}/usageEvents/{generationId}`.
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
3. Read `premium`/`plan` and current usage from Firestore inside the trusted Worker request that authorizes or finalizes quota. Do not authorize from stale client memory or D1.
4. Update the UI from the authoritative response or Firestore listener after a successful mutation.
5. Make retries idempotent. Firestore `usageEvents/{generationId}` is created in the same atomic commit as the quota/usage mutation, so a network retry cannot consume twice.
6. Do not charge a free generation for a failed provider request. Provider cost and tokens are still recorded for failed/expired requests that reached DeepSeek.
7. D1 is operational storage only: generation sessions, provider-call idempotency, encrypted retry responses, prompt configuration, and a replaceable usage cache. Every authorization starts from Firestore, and D1 usage rows are overwritten from the canonical Firestore snapshot.
8. Test at least free request 1, free request 5, rejected request 6, free 31-card rejection, premium 100-card acceptance, premium 101-card rejection, plan changes while the app is open, and two concurrent requests.

## DeepSeek Production Boundary

The trusted production boundary is the `quizflash-ai` Cloudflare Worker, not Firebase Cloud Functions. Read `ai-proxy.md` before changing this flow.

1. Keep `DEEPSEEK_API_KEY`, `FIREBASE_SERVICE_ACCOUNT_JSON`, and `RESPONSE_CACHE_ENCRYPTION_KEY` only as Cloudflare Worker secrets. Never place their values in the app, repository, Firestore, traces, screenshots, or chat.
2. Release iOS sends the OpenAI-compatible DeepSeek body through the Worker. The Worker validates auth/session/model/minimal structure, then forwards raw request bytes and returns raw response bytes without prompt rewriting, JSON repair, DTO mapping, title generation, or LaTeX processing.
3. Enforce free/premium card limits, free quota, and premium monthly budget in the Worker from canonical Firestore values. Use Durable Objects for per-user concurrency and D1 for operational sessions, telemetry, prompt configuration, and retry caching.
4. Keep iOS as the owner of planner allocations, dynamic message composition, retries, generated-title flow, card DTO decoding, LaTeX normalization, and SwiftData insertion. Title and card requests must share the same transparent proxy path.
5. Record only operational metadata in D1: generation/provider-call IDs, model, token usage, estimated `microUSD` cost, response status, duration, and encrypted short-lived retry response. Do not store source text or prompt text in telemetry.
6. Derive cost from the response model plus cache-hit, cache-miss, and completion token usage. Do not use the client-requested model alias as the billing source.
7. Keep `AIProviderStore` only for DEBUG developer profiles. Release builds must use `CloudAIProxyClient` and never send an API key.
8. Prompt configuration may be backend-owned for iteration, but it does not authorize anything. Preserve the transparent raw provider transport and use versioned cached templates so a prompt update never requires an app update or a new per-request network round trip.

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

1. `npm run build` and `npm test` in `worker/`, then the targeted iOS `xcodebuild` destination.
2. Firestore rules behavior for owner/non-owner and protected fields.
3. Fresh account, free-limit boundary, premium boundary, entitlement downgrade, sign-out/sign-in, and app relaunch.
4. Function error mapping for unauthenticated, invalid target count, quota exhausted, provider rate limit, provider malformed JSON, and timeout.
5. RevenueCat sandbox purchase, restore, renewal/cancellation simulation, webhook delivery, Firebase document/claim update, and cross-device refresh.

Report what ran, what reached Firebase, and every remaining deployment or platform blocker. Do not say an integration is complete while it remains source-only or a required remote configuration is missing.
