# AI Proxy Contract

Read this reference before changing DeepSeek transport, prompt ownership, AI quota, cost accounting, or Cloudflare Worker behavior.

## Live Topology

- Production Worker: `quizflash-ai`.
- Public Worker URL: `https://quizflash-ai.quizflash-platform.workers.dev`.
- Worker source: `worker/`; entry point: `worker/src/index.ts`.
- Release endpoint configuration: `QuizFlash/Info.plist`, key `AIProxyBaseURL`.
- Firebase project: `quizflash-6b0ea`.
- D1 binding: `AI_DB` (`quizflash-ai`).
- Durable Object binding: `USER_GENERATION`, one coordinator per Firebase UID.
- Worker secrets, by name only: `DEEPSEEK_API_KEY`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `RESPONSE_CACHE_ENCRYPTION_KEY`.

Do not place a secret value in source, app configuration, trace payloads, logs, screenshots, or messages.

## Current Release Flow

1. The final Generate action calls `CloudAIProxyClient.startGeneration` with a Firebase ID token, target-card count, and idempotency key.
2. `POST /v1/generations/start` verifies Firebase Auth, reads canonical entitlement and current-month usage from Firestore, then creates the operational session through the UID Durable Object.
3. `AIFlashcardService` keeps its local planner and builds the exact OpenAI-compatible request body: model, messages, response format, temperature, and thinking options.
4. `AIRequestTransport.cloudProxy` changes only the destination and adds generation/session/provider-call headers. `POST /v1/chat/completions` forwards the received body bytes to DeepSeek and returns the response bytes unchanged.
5. iOS runs the existing title parser, retry policy, JSON/DTO decoding, LaTeX normalization, and local deck/card insertion. Both title and card batches use the same proxy.
6. iOS calls `/finish` with validated-card count or `/fail` after cancellation/no usable output. The Worker atomically finalizes canonical Firestore usage with a server-only `usageEvents/{generationId}` idempotency record, then replaces the D1 cache from that Firestore result.

### Ownership Boundaries

| iOS owns | Worker owns |
| --- | --- |
| Planner, source extraction, dynamic prompt composition, title generation, retry strategy, DTO decoding, LaTeX normalization, SwiftData insertion | Firebase token validation, Firestore-authoritative entitlement/quota/usage, concurrency, idempotency, DeepSeek key, raw proxying, token/cost audit |

### Usage Authority

- Firestore is the only source of truth for plan, free quota, and monthly AI usage.
- Canonical monthly usage lives at `users/{uid}/usage/{YYYYMM}`.
- D1 usage tables are caches and operational telemetry. The Worker must never push a stale D1 counter into Firestore.
- An admin edit in Firestore affects the next entitlement/start/finalization request. That request also replaces the corresponding D1 cache row.
- Failed or expired generations do not consume a free generation, but any provider cost/tokens already incurred are finalized in monthly Firestore usage.

Do not move parsing, JSON repair, escaping repair, title parsing, prompt rewriting, card mapping, or card persistence into the Worker. Those changes previously caused visible regressions in generated-card formatting.

## Worker Routes

- `POST /v1/generations/start`: authenticates and starts/resumes a generation session.
- `POST /v1/chat/completions`: transparent provider proxy. Required headers: generation ID, session token, Firebase UID, operation (`title` or `cards`), and stable provider call ID.
- `POST /v1/generations/finish`: finalizes a completed/partial generation using locally validated-card count.
- `POST /v1/generations/fail`: releases a failed/cancelled reservation.
- `GET /v1/entitlements`: returns current entitlement/quota state.
- `GET /health`: deployment health check.

The Worker may parse a cloned provider response only for usage/cost telemetry. It must return the original response bytes and relevant status/header semantics to iOS.

## Prompt Configuration Migration

The desired state is backend-owned prompt text with iOS-owned composition:

1. Store a versioned prompt bundle in Worker-controlled storage. The bundle contains text/templates only, never source text or user data.
2. Preserve the current Swift composition order and dynamic substitutions. iOS supplies values such as target count, card type, depth, language hint, batch/source labels, covered prompts, and OCR mode.
3. Do not add a new synchronous prompt fetch before each DeepSeek request. Reuse the generation-start response and keep a persistent versioned iOS cache.
4. On a cache hit, start generation immediately with the cached server bundle. On a version mismatch, obtain the new bundle from the already-required start response, validate it, cache it, then compose messages.
5. Prefetch/refresh configuration in background when the AI picker opens or the app becomes active. Never delay presentation of the picker for configuration loading.
6. A first install or first generation after a prompt version change can require one bundle transfer. This is unavoidable if the app has no local copy; it must occur within the existing start/loading state, not as a separate provider-request round trip.

A remote prompt is a quality/configuration control, not a security control. Because iOS receives the text and the Worker transparently forwards raw bytes, a modified client can still send different prompt text. Quota, spending, and provider-key protection remain server-enforced.

## Performance Invariants

- Keep the Worker raw-pass-through for `/v1/chat/completions`.
- Do not add a second network hop between iOS and DeepSeek.
- Do not decode and re-encode the provider envelope in the Worker.
- Preserve stable `providerCallId` across an iOS retry so the encrypted 15-minute response cache prevents duplicate provider calls/cost.
- Emit and preserve `Server-Timing` and request IDs for latency analysis.
- Treat an added user-visible delay as a regression. Measure start/configuration and provider timings separately.

## Verification And Deployment

1. Run `npm run build` and `npm test` in `worker/`.
2. Run a targeted iOS test/build on iPhone 15 Pro iOS 17.5.
3. Contract-test direct fixture versus proxy fixture: same request bytes must yield identical title/card decoding and LaTeX normalization.
4. Test free quota boundary, free 31-card rejection, premium 100-card acceptance, premium 101-card rejection, same idempotency key, provider failure, and cancellation.
5. Deploy with `wrangler deploy` from `worker/`; verify `GET /health` afterward.
6. For a prompt-bundle change, verify the version/hash recorded in local AI trace, a cache hit does not add a network request, and a version change updates the next generation without an app update.
