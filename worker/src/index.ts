import { DurableObject } from "cloudflare:workers";
import {defaultPromptBundle, type PromptBundleRecord, validatedPromptBundle} from "./promptBundle";

type Env = {
  AI_DB: D1Database;
  USER_GENERATION: DurableObjectNamespace<UserGenerationCoordinator>;
  DEEPSEEK_API_KEY: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
  RESPONSE_CACHE_ENCRYPTION_KEY: string;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_WEB_API_KEY: string;
  DEEPSEEK_BASE_URL: string;
  DEEPSEEK_MODEL: string;
  PREMIUM_MONTHLY_AI_BUDGET_MICRO_USD: string;
};

type Entitlement = {
  uid: string;
  premium: boolean;
  freeGenerationsUsed: number;
  freeGenerationsLimit: number;
};

type StartRequest = {
  idempotencyKey?: unknown;
  targetCards?: unknown;
  knownPromptVersion?: unknown;
};

type SessionStart = {
  idempotencyKey: string;
  targetCards: number;
  entitlement: Entitlement;
  promptVersion: string;
  promptHash: string;
};

type SessionState = {
  generationId: string;
  idempotencyKey: string;
  sessionToken: string;
  uid: string;
  premium: boolean;
  targetCards: number;
  expiresAtMs: number;
};

type QuotaResponse = {
  premium: boolean;
  freeGenerationsUsed: number | null;
  freeGenerationsLimit: number | null;
  monthlyCostMicroUSD: number;
  limitMicroUSD: number | null;
  consumedMicroUSD: number;
  reservedMicroUSD: number;
  availableMicroUSD: number | null;
  percent: number | null;
};

type GenerationSessionResponse = {
  generationId: string;
  sessionToken: string;
  targetCards: number;
  expiresAt: string;
  quota: QuotaResponse;
  usageQuota: QuotaResponse;
};

type SessionStartResult =
  | {kind: "session"; session: GenerationSessionResponse}
  | {kind: "rejection"; status: number; code: string; message: string; usageQuota?: QuotaResponse};

type ProviderUsage = {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  prompt_cache_hit_tokens?: number;
  prompt_cache_miss_tokens?: number;
};

type ProviderEnvelope = {
  id?: string;
  model?: string;
  usage?: ProviderUsage;
  choices?: Array<{ finish_reason?: string }>;
};

type StoredProviderCall = {
  provider_call_id: string;
  http_status: number;
  response_ciphertext: string | null;
  response_iv: string | null;
  response_expires_at_ms: number | null;
};

type StoredPromptConfig = {
  version: string;
  hash: string;
  status: "draft" | "active" | "retired";
  templates_json: string;
};

type UsageReservation = {
  providerCallId: string;
  generationId: string;
  uid: string;
  period: string;
  reservedCostMicroUSD: number;
  expiresAtMs: number;
};

type ProviderCallAccountingInput = {
  providerCallId: string;
  generationId: string;
  operation: string;
  requestedModel: string;
  httpStatus: number;
  rawResponseBytes: number;
  metadata: ProviderMetadata;
  responseCiphertext: string;
  responseIV: string;
  responseExpiresAtMs: number;
  createdAtMs: number;
};

type ProviderCallAccountingResult = {
  quota: QuotaResponse;
  event: UsageEventResponse;
};

type UsageEventResponse = {
  providerCallId: string;
  pricingVersion: string;
  accountingStatus: ProviderAccountingStatus;
  costMicroUSD: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  responseModel: string | null;
};

type ProviderAccountingStatus = "accounted" | "accounting_error" | "not_billable";

const freeLifetimeGenerationLimit = 5;
const freeMaxCardsPerGeneration = 30;
const premiumMaxCardsPerGeneration = 100;
const premiumPlan = "premium";
const monthlyPeriod = "monthly";
const defaultPremiumMonthlyBudgetMicroUSD = 2_000_000;
const pricingVersion = "deepseek-v4-flash@2026-06";
const activeSessionTTLMilliseconds = 20 * 60 * 1_000;
const providerResponseTTLMilliseconds = 15 * 60 * 1_000;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export class UserGenerationCoordinator extends DurableObject<Env> {
  private queue: Promise<void> = Promise.resolve();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  async start(input: SessionStart): Promise<SessionStartResult> {
    return this.enqueue(() => this.startLocked(input));
  }

  private async startLocked(input: SessionStart): Promise<SessionStartResult> {
    const now = Date.now();
    const active = await this.ctx.storage.get<SessionState>("active");
    if (active && active.expiresAtMs > now && active.idempotencyKey !== input.idempotencyKey) {
      return sessionRejection(429, "resource-exhausted", "Another AI generation is already running.");
    }

    const existing = await this.env.AI_DB.prepare(
      "SELECT id, status, premium, target_cards FROM ai_generations WHERE uid = ? AND idempotency_key = ?"
    ).bind(input.entitlement.uid, input.idempotencyKey).first<{ id: string; status: string; premium: number; target_cards: number }>();

    if (existing?.status === "succeeded" || existing?.status === "partial") {
      return {
        kind: "session",
        session: await this.sessionResponse(existing.id, input.entitlement.uid, existing.premium === 1, existing.target_cards, now)
      };
    }

    const quota = await this.ensureFreeQuota(input.entitlement, now);
    if (!input.entitlement.premium && quota.used >= quota.limit) {
      return sessionRejection(429, "resource-exhausted", "Free AI generation limit reached.", await this.entitlementResponse(input.entitlement.uid, false));
    }

    const maxCards = input.entitlement.premium ? premiumMaxCardsPerGeneration : freeMaxCardsPerGeneration;
    if (input.targetCards > maxCards) {
      return sessionRejection(412, "failed-precondition", `This plan allows up to ${maxCards} cards per generation.`);
    }

    if (input.entitlement.premium) {
      const usageQuota = await this.entitlementResponse(input.entitlement.uid, true);
      if ((usageQuota.availableMicroUSD ?? 0) <= 0) {
        return sessionRejection(429, "AI_QUOTA_EXHAUSTED", "Monthly AI budget reached.", usageQuota);
      }
    }

    const generationId = existing?.id ?? crypto.randomUUID();
    if (!existing) {
      await this.env.AI_DB.prepare(
        `INSERT INTO ai_generations (
          id, uid, idempotency_key, status, premium, target_cards, prompt_version, prompt_hash, created_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, 'reserved', ?, ?, ?, ?, ?, ?)`
      ).bind(
        generationId,
        input.entitlement.uid,
        input.idempotencyKey,
        input.entitlement.premium ? 1 : 0,
        input.targetCards,
        input.promptVersion,
        input.promptHash,
        now,
        now
      ).run();
    }

    const response = await this.sessionResponse(generationId, input.entitlement.uid, input.entitlement.premium, input.targetCards, now);
    await this.ctx.storage.put("active", {
      generationId,
      idempotencyKey: input.idempotencyKey,
      sessionToken: response.sessionToken as string,
      uid: input.entitlement.uid,
      premium: input.entitlement.premium,
      targetCards: input.targetCards,
      expiresAtMs: now + activeSessionTTLMilliseconds
    } satisfies SessionState);
    await this.ctx.storage.setAlarm(now + activeSessionTTLMilliseconds);
    return {kind: "session", session: response};
  }

  async authorize(generationId: string, sessionToken: string): Promise<SessionState> {
    const active = await this.ctx.storage.get<SessionState>("active");
    if (!active || active.generationId !== generationId || active.expiresAtMs <= Date.now() || active.sessionToken !== sessionToken) {
      throw new WorkerError(401, "unauthenticated", "AI generation session is invalid or expired.");
    }
    return active;
  }

  async finish(generationId: string, sessionToken: string, validatedCards: number): Promise<QuotaResponse> {
    return this.enqueue(() => this.finishLocked(generationId, sessionToken, validatedCards));
  }

  private async finishLocked(generationId: string, sessionToken: string, validatedCards: number): Promise<QuotaResponse> {
    const active = await this.authorize(generationId, sessionToken);
    const now = Date.now();
    const finalStatus = validatedCards > 0 && validatedCards < active.targetCards ? "partial" : "succeeded";
    const generation = await this.env.AI_DB.prepare(
      "SELECT uid, premium FROM ai_generations WHERE id = ?"
    ).bind(generationId).first<{ uid: string; premium: number }>();
    if (!generation) throw new WorkerError(404, "not-found", "AI generation was not found.");

    const statements: D1PreparedStatement[] = [
      this.env.AI_DB.prepare(
        "UPDATE ai_generations SET status = ?, validated_cards = ?, updated_at_ms = ?, completed_at_ms = ? WHERE id = ?"
      ).bind(finalStatus, validatedCards, now, now, generationId),
      this.env.AI_DB.prepare(
        `INSERT INTO ai_monthly_usage (uid, period, generated_cards, request_count, cost_micro_usd, updated_at_ms)
         VALUES (?, ?, ?, 1, 0, ?)
         ON CONFLICT(uid, period) DO UPDATE SET
           generated_cards = generated_cards + excluded.generated_cards,
           request_count = request_count + 1,
           updated_at_ms = excluded.updated_at_ms`
      ).bind(generation.uid, monthKey(now), validatedCards, now)
    ];
    if (generation.premium === 0 && validatedCards > 0) {
      statements.push(this.env.AI_DB.prepare(
        "UPDATE ai_free_quota SET used_generations = used_generations + 1, updated_at_ms = ? WHERE uid = ?"
      ).bind(now, generation.uid));
    }
    await this.env.AI_DB.batch(statements);
    await this.clearActive(generationId);
    return this.entitlementResponse(generation.uid, generation.premium === 1);
  }

  async fail(generationId: string, sessionToken: string): Promise<QuotaResponse> {
    return this.enqueue(() => this.failLocked(generationId, sessionToken));
  }

  private async failLocked(generationId: string, sessionToken: string): Promise<QuotaResponse> {
    await this.authorize(generationId, sessionToken);
    const now = Date.now();
    const generation = await this.env.AI_DB.prepare(
      "SELECT uid, premium FROM ai_generations WHERE id = ?"
    ).bind(generationId).first<{ uid: string; premium: number }>();
    if (!generation) throw new WorkerError(404, "not-found", "AI generation was not found.");
    await this.env.AI_DB.prepare(
      "UPDATE ai_generations SET status = 'failed', updated_at_ms = ?, completed_at_ms = ? WHERE id = ? AND status = 'reserved'"
    ).bind(now, now, generationId).run();
    await this.clearActive(generationId);
    return this.entitlementResponse(generation.uid, generation.premium === 1);
  }

  async entitlement(entitlement: Entitlement): Promise<QuotaResponse> {
    await this.ensureFreeQuota(entitlement, Date.now());
    return this.entitlementResponse(entitlement.uid, entitlement.premium);
  }

  async usageQuotaForSession(generationId: string, sessionToken: string): Promise<QuotaResponse> {
    const active = await this.authorize(generationId, sessionToken);
    return this.entitlementResponse(active.uid, active.premium);
  }

  async reserveProviderCall(generationId: string, sessionToken: string, providerCallId: string): Promise<QuotaResponse> {
    return this.enqueue(async () => {
      const active = await this.authorize(generationId, sessionToken);
      const existing = await this.env.AI_DB.prepare(
        "SELECT provider_call_id FROM ai_provider_calls WHERE provider_call_id = ?"
      ).bind(providerCallId).first<{ provider_call_id: string }>();
      if (existing || !active.premium) return this.entitlementResponse(active.uid, active.premium);

      const quota = await this.entitlementResponse(active.uid, true);
      const available = quota.availableMicroUSD ?? 0;
      if (available <= 0) {
        throw new WorkerError(429, "AI_QUOTA_EXHAUSTED", "Monthly AI budget reached.", quota);
      }

      const now = Date.now();
      const period = monthKey(now);
      await this.env.AI_DB.prepare(
        `INSERT INTO ai_monthly_usage (uid, period, generated_cards, request_count, cost_micro_usd, reserved_cost_micro_usd, updated_at_ms)
         VALUES (?, ?, 0, 0, 0, ?, ?)
         ON CONFLICT(uid, period) DO UPDATE SET
           reserved_cost_micro_usd = reserved_cost_micro_usd + excluded.reserved_cost_micro_usd,
           updated_at_ms = excluded.updated_at_ms`
      ).bind(active.uid, period, available, now).run();
      await this.ctx.storage.put(`reservation:${providerCallId}`, {
        providerCallId,
        generationId,
        uid: active.uid,
        period,
        reservedCostMicroUSD: available,
        expiresAtMs: now + providerResponseTTLMilliseconds
      } satisfies UsageReservation);
      await this.ctx.storage.setAlarm(Math.min(active.expiresAtMs, now + providerResponseTTLMilliseconds));
      return this.entitlementResponse(active.uid, true);
    });
  }

  async releaseProviderCallReservation(providerCallId: string): Promise<void> {
    await this.enqueue(() => this.releaseReservation(providerCallId, Date.now()));
  }

  async finalizeProviderCall(input: ProviderCallAccountingInput): Promise<ProviderCallAccountingResult> {
    return this.enqueue(async () => {
      const generation = await this.env.AI_DB.prepare(
        "SELECT uid, premium FROM ai_generations WHERE id = ?"
      ).bind(input.generationId).first<{ uid: string; premium: number }>();
      if (!generation) throw new WorkerError(404, "not-found", "AI generation was not found.");

      const existing = await this.env.AI_DB.prepare(
        "SELECT provider_call_id FROM ai_provider_calls WHERE provider_call_id = ?"
      ).bind(input.providerCallId).first<{ provider_call_id: string }>();
      if (existing) {
        await this.releaseReservation(input.providerCallId, input.createdAtMs);
        const quota = await this.entitlementResponse(generation.uid, generation.premium === 1);
        return {quota, event: usageEvent(input.providerCallId, input.metadata)};
      }

      const statements: D1PreparedStatement[] = [
        this.env.AI_DB.prepare(
          `INSERT INTO ai_provider_calls (
            provider_call_id, generation_id, operation, requested_model, response_model, provider_response_id,
            http_status, finish_reason, raw_response_bytes, prompt_tokens, completion_tokens, total_tokens,
            cache_hit_tokens, cache_miss_tokens, estimated_cost_micro_usd, final_cost_micro_usd,
            pricing_version, accounting_status, accounted_at_ms, response_ciphertext, response_iv,
            response_expires_at_ms, created_at_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(
          input.providerCallId, input.generationId, input.operation, input.requestedModel, input.metadata.model, input.metadata.responseID,
          input.httpStatus, input.metadata.finishReason, input.rawResponseBytes, input.metadata.promptTokens, input.metadata.completionTokens,
          input.metadata.totalTokens, input.metadata.cacheHitTokens, input.metadata.cacheMissTokens, input.metadata.costMicroUSD,
          input.metadata.costMicroUSD, input.metadata.pricingVersion, input.metadata.accountingStatus,
          input.metadata.accountingStatus === "accounted" ? input.createdAtMs : null,
          input.responseCiphertext, input.responseIV, input.responseExpiresAtMs, input.createdAtMs
        )
      ];

      const reservationKey = `reservation:${input.providerCallId}`;
      const reservation = await this.ctx.storage.get<UsageReservation>(reservationKey);
      if (reservation) {
        statements.push(this.env.AI_DB.prepare(
          `UPDATE ai_monthly_usage
           SET reserved_cost_micro_usd = MAX(0, reserved_cost_micro_usd - ?), updated_at_ms = ?
           WHERE uid = ? AND period = ?`
        ).bind(reservation.reservedCostMicroUSD, input.createdAtMs, reservation.uid, reservation.period));
      }

      if (input.metadata.accountingStatus === "accounted") {
        const cost = input.metadata.costMicroUSD;
        statements.push(
          this.env.AI_DB.prepare(
            `UPDATE ai_generations SET
              status = 'running', total_prompt_tokens = total_prompt_tokens + ?,
              total_completion_tokens = total_completion_tokens + ?, total_tokens = total_tokens + ?,
              total_cache_hit_tokens = total_cache_hit_tokens + ?, total_cache_miss_tokens = total_cache_miss_tokens + ?,
              cost_micro_usd = cost_micro_usd + ?, updated_at_ms = ? WHERE id = ?`
          ).bind(input.metadata.promptTokens, input.metadata.completionTokens, input.metadata.totalTokens, input.metadata.cacheHitTokens, input.metadata.cacheMissTokens, cost, input.createdAtMs, input.generationId),
          this.env.AI_DB.prepare(
            `INSERT INTO ai_monthly_usage (uid, period, generated_cards, request_count, cost_micro_usd, reserved_cost_micro_usd, updated_at_ms)
             VALUES (?, ?, 0, 0, ?, 0, ?)
             ON CONFLICT(uid, period) DO UPDATE SET
               cost_micro_usd = cost_micro_usd + excluded.cost_micro_usd,
               updated_at_ms = excluded.updated_at_ms`
          ).bind(generation.uid, monthKey(input.createdAtMs), cost, input.createdAtMs)
        );
      } else if (input.httpStatus >= 200 && input.httpStatus <= 299 && input.metadata.accountingStatus === "accounting_error") {
        console.error(JSON.stringify({
          event: "provider_accounting_error",
          generation_id: input.generationId,
          provider_call_id: input.providerCallId,
          response_model: input.metadata.model,
          usage_present: input.metadata.usagePresent
        }));
      }

      await this.env.AI_DB.batch(statements);
      if (reservation) await this.ctx.storage.delete(reservationKey);
      const quota = await this.entitlementResponse(generation.uid, generation.premium === 1);
      return {quota, event: usageEvent(input.providerCallId, input.metadata)};
    });
  }

  async alarm(): Promise<void> {
    await this.enqueue(async () => {
      const now = Date.now();
      const reservations = await this.ctx.storage.list<UsageReservation>({prefix: "reservation:"});
      for (const key of reservations.keys()) {
        const reservation = reservations.get(key);
        if (reservation && reservation.expiresAtMs <= now) {
          await this.releaseReservation(reservation.providerCallId, now);
        }
      }

      const active = await this.ctx.storage.get<SessionState>("active");
      if (active && active.expiresAtMs <= Date.now()) {
        await this.env.AI_DB.prepare(
          "UPDATE ai_generations SET status = 'expired', updated_at_ms = ? WHERE id = ? AND status = 'reserved'"
        ).bind(Date.now(), active.generationId).run();
        await this.clearActive(active.generationId);
      }
    });
  }

  private async sessionResponse(generationId: string, uid: string, premium: boolean, targetCards: number, now: number): Promise<GenerationSessionResponse> {
    const sessionToken = await sessionTokenFor(generationId, this.env.RESPONSE_CACHE_ENCRYPTION_KEY);
    const usageQuota = await this.entitlementResponse(uid, premium);
    return {
      generationId,
      sessionToken,
      targetCards,
      expiresAt: new Date(now + activeSessionTTLMilliseconds).toISOString(),
      quota: usageQuota,
      usageQuota
    };
  }

  private async entitlementResponse(uid: string, premium: boolean): Promise<QuotaResponse> {
    const quota = await this.env.AI_DB.prepare(
      "SELECT used_generations, limit_generations FROM ai_free_quota WHERE uid = ?"
    ).bind(uid).first<{ used_generations: number; limit_generations: number }>();
    const monthly = await this.env.AI_DB.prepare(
      "SELECT cost_micro_usd, reserved_cost_micro_usd FROM ai_monthly_usage WHERE uid = ? AND period = ?"
    ).bind(uid, monthKey(Date.now())).first<{ cost_micro_usd: number; reserved_cost_micro_usd: number }>();
    const consumed = Math.max(0, monthly?.cost_micro_usd ?? 0);
    const reserved = Math.max(0, monthly?.reserved_cost_micro_usd ?? 0);
    const limit = premium ? await activePlanLimitMicroUSD(this.env, premiumPlan) : null;
    const available = limit === null ? null : Math.max(0, limit - consumed - reserved);
    const percent = limit && limit > 0 ? Math.min(1, (consumed + reserved) / limit) : null;
    return {
      premium,
      freeGenerationsUsed: premium ? null : quota?.used_generations ?? 0,
      freeGenerationsLimit: premium ? null : quota?.limit_generations ?? freeLifetimeGenerationLimit,
      monthlyCostMicroUSD: consumed,
      limitMicroUSD: limit,
      consumedMicroUSD: consumed,
      reservedMicroUSD: reserved,
      availableMicroUSD: available,
      percent
    };
  }

  private async ensureFreeQuota(entitlement: Entitlement, now: number): Promise<{ used: number; limit: number }> {
    const existing = await this.env.AI_DB.prepare(
      "SELECT used_generations, limit_generations FROM ai_free_quota WHERE uid = ?"
    ).bind(entitlement.uid).first<{ used_generations: number; limit_generations: number }>();
    if (existing) return {used: existing.used_generations, limit: existing.limit_generations};
    const used = Math.max(0, entitlement.freeGenerationsUsed);
    const limit = Math.max(1, entitlement.freeGenerationsLimit || freeLifetimeGenerationLimit);
    await this.env.AI_DB.prepare(
      "INSERT INTO ai_free_quota (uid, used_generations, limit_generations, initialized_at_ms, updated_at_ms) VALUES (?, ?, ?, ?, ?)"
    ).bind(entitlement.uid, used, limit, now, now).run();
    return {used, limit};
  }

  private async clearActive(generationId: string): Promise<void> {
    const active = await this.ctx.storage.get<SessionState>("active");
    if (active?.generationId === generationId) {
      await this.ctx.storage.delete("active");
      await this.ctx.storage.deleteAlarm();
    }
  }

  private async releaseReservation(providerCallId: string, now: number): Promise<UsageReservation | undefined> {
    const key = `reservation:${providerCallId}`;
    const reservation = await this.ctx.storage.get<UsageReservation>(key);
    if (!reservation) return undefined;
    await this.env.AI_DB.prepare(
      `UPDATE ai_monthly_usage
       SET reserved_cost_micro_usd = MAX(0, reserved_cost_micro_usd - ?), updated_at_ms = ?
       WHERE uid = ? AND period = ?`
    ).bind(reservation.reservedCostMicroUSD, now, reservation.uid, reservation.period).run();
    await this.ctx.storage.delete(key);
    return reservation;
  }

  private async enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.queue.then(operation, operation);
    this.queue = next.then(() => undefined, () => undefined);
    return next;
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const startedAt = performance.now();
    const requestID = crypto.randomUUID();
    const url = new URL(request.url);
    try {
      if (request.method === "POST" && url.pathname === "/v1/generations/start") {
        return timedJSON(await startGeneration(request, env), startedAt, requestID);
      }
      if (request.method === "POST" && url.pathname === "/v1/generations/finish") {
        return timedJSON(await finishGeneration(request, env, false), startedAt, requestID);
      }
      if (request.method === "POST" && url.pathname === "/v1/generations/fail") {
        return timedJSON(await finishGeneration(request, env, true), startedAt, requestID);
      }
      if (request.method === "GET" && url.pathname === "/v1/entitlements") {
        return timedJSON(await readEntitlement(request, env), startedAt, requestID);
      }
      if (request.method === "GET" && url.pathname === "/v1/prompt-config") {
        return timedJSON(await readPromptConfig(request, env), startedAt, requestID);
      }
      if (request.method === "POST" && url.pathname === "/v1/chat/completions") {
        return proxyCompletion(request, env, startedAt);
      }
      if (request.method === "GET" && url.pathname === "/health") return timedJSON({ok: true}, startedAt, requestID);
      throw new WorkerError(404, "not-found", "Endpoint not found.");
    } catch (error) {
      return errorResponse(error, startedAt, requestID, url.pathname);
    }
  },
  async scheduled(_: ScheduledController, env: Env): Promise<void> {
    await env.AI_DB.prepare(
      "DELETE FROM ai_provider_calls WHERE response_expires_at_ms IS NOT NULL AND response_expires_at_ms <= ?"
    ).bind(Date.now()).run();
  }
} satisfies ExportedHandler<Env>;

async function startGeneration(request: Request, env: Env): Promise<Record<string, unknown>> {
  let stage = "authenticate";
  try {
    const idToken = bearerToken(request);
    const uid = await verifyFirebaseIDToken(idToken, env);
    stage = "parse_request";
    const payload = await request.json<StartRequest>();
    const targetCards = positiveInteger(payload.targetCards, "targetCards");
    const idempotencyKey = nonEmptyString(payload.idempotencyKey, "idempotencyKey", 128);
    const knownPromptVersion = optionalString(payload.knownPromptVersion, "knownPromptVersion", 64);
    stage = "prompt_config";
    const promptConfig = await activePromptConfig(env);
    stage = "entitlement";
    const profile = await readFirestoreProfile(uid, env);
    const entitlement: Entitlement = {
      uid,
      premium: profile.premium,
      freeGenerationsUsed: profile.freeGenerationsUsed,
      freeGenerationsLimit: profile.freeGenerationsLimit
    };
    stage = "session_reservation";
    const stub = env.USER_GENERATION.getByName(uid);
    const startResult = await stub.start({
      idempotencyKey,
      targetCards,
      entitlement,
      promptVersion: promptConfig.version,
      promptHash: promptConfig.hash
    });
    if (startResult.kind === "rejection") {
      throw new WorkerError(startResult.status, startResult.code, startResult.message, startResult.usageQuota);
    }
    return promptStartResponse({...startResult.session}, promptConfig, knownPromptVersion);
  } catch (error) {
    if (!(error instanceof WorkerError)) {
      console.error(JSON.stringify({event: "generation_start_failed", stage, error_name: errorName(error)}));
    }
    throw error;
  }
}

async function readPromptConfig(request: Request, env: Env): Promise<Record<string, unknown>> {
  await verifyFirebaseIDToken(bearerToken(request), env);
  const knownPromptVersion = optionalString(new URL(request.url).searchParams.get("knownPromptVersion"), "knownPromptVersion", 64);
  return promptConfigResponse(await activePromptConfig(env), knownPromptVersion);
}

async function activePromptConfig(env: Env): Promise<PromptBundleRecord> {
  const active = await env.AI_DB.prepare(
    "SELECT version, hash, status, templates_json FROM ai_prompt_configs WHERE status = 'active' LIMIT 1"
  ).first<StoredPromptConfig>();
  if (active) {
    const validated = await validatedPromptBundle({
      version: active.version,
      status: active.status,
      templates: JSON.parse(active.templates_json) as Record<string, string>
    });
    if (validated.hash !== active.hash) throw new WorkerError(500, "internal", "Active prompt configuration hash is invalid.");
    return validated;
  }

  const seeded = await validatedPromptBundle(defaultPromptBundle);
  const now = Date.now();
  await env.AI_DB.prepare(
    "INSERT OR IGNORE INTO ai_prompt_configs (version, hash, status, templates_json, created_at_ms, activated_at_ms) VALUES (?, ?, 'active', ?, ?, ?)"
  ).bind(seeded.version, seeded.hash, JSON.stringify(seeded.templates), now, now).run();
  return seeded;
}

async function activePlanLimitMicroUSD(env: Env, plan: string): Promise<number> {
  const configured = await env.AI_DB.prepare(
    "SELECT limit_micro_usd FROM ai_plan_limits WHERE plan = ? AND period = ? AND active = 1 ORDER BY updated_at_ms DESC LIMIT 1"
  ).bind(plan, monthlyPeriod).first<{ limit_micro_usd: number }>();
  if (configured) return Math.max(0, configured.limit_micro_usd);
  return fallbackPremiumMonthlyBudgetMicroUSD(env);
}

function fallbackPremiumMonthlyBudgetMicroUSD(env: Env): number {
  const parsed = Number(env.PREMIUM_MONTHLY_AI_BUDGET_MICRO_USD);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : defaultPremiumMonthlyBudgetMicroUSD;
}

export function promptStartResponse(session: Record<string, unknown>, promptConfig: PromptBundleRecord, knownPromptVersion: string | undefined): Record<string, unknown> {
  return {
    ...session,
    ...promptConfigResponse(promptConfig, knownPromptVersion)
  };
}

export function promptConfigResponse(promptConfig: PromptBundleRecord, knownPromptVersion: string | undefined): Record<string, unknown> {
  const response: Record<string, unknown> = {
    promptVersion: promptConfig.version,
    promptHash: promptConfig.hash
  };
  if (knownPromptVersion !== promptConfig.version) {
    response.promptBundle = promptConfig;
  }
  return response;
}

async function finishGeneration(request: Request, env: Env, failed: boolean): Promise<Record<string, unknown>> {
  const payload = await request.json<Record<string, unknown>>();
  const generationId = nonEmptyString(payload.generationId, "generationId", 128);
  const sessionToken = nonEmptyString(payload.sessionToken, "sessionToken", 256);
  const stub = env.USER_GENERATION.getByName(nonEmptyString(request.headers.get("X-QuizFlash-UID"), "X-QuizFlash-UID", 128));
  if (failed) {
    const usageQuota = await stub.fail(generationId, sessionToken);
    return {status: "failed", usageQuota, quota: usageQuota};
  }
  const usageQuota = await stub.finish(generationId, sessionToken, Math.max(0, Number(payload.validatedCards) || 0));
  return {usageQuota, quota: usageQuota};
}

async function readEntitlement(request: Request, env: Env): Promise<Record<string, unknown>> {
  const uid = await verifyFirebaseIDToken(bearerToken(request), env);
  const profile = await readFirestoreProfile(uid, env);
  return {...await env.USER_GENERATION.getByName(uid).entitlement({
    uid,
    premium: profile.premium,
    freeGenerationsUsed: profile.freeGenerationsUsed,
    freeGenerationsLimit: profile.freeGenerationsLimit
  })};
}

async function proxyCompletion(request: Request, env: Env, startedAt: number): Promise<Response> {
  const generationId = nonEmptyString(request.headers.get("X-QuizFlash-Generation-ID"), "X-QuizFlash-Generation-ID", 128);
  const sessionToken = nonEmptyString(request.headers.get("X-QuizFlash-Session"), "X-QuizFlash-Session", 256);
  const providerCallId = nonEmptyString(request.headers.get("X-QuizFlash-Provider-Call-ID"), "X-QuizFlash-Provider-Call-ID", 128);
  const operation = request.headers.get("X-QuizFlash-Operation") === "title" ? "title" : "cards";
  const uid = nonEmptyString(request.headers.get("X-QuizFlash-UID"), "X-QuizFlash-UID", 128);
  const stub = env.USER_GENERATION.getByName(uid);
  await stub.authorize(generationId, sessionToken);
  const rawBody = await request.arrayBuffer();
  const requestPayload = parseProviderRequest(rawBody, env.DEEPSEEK_MODEL);
  const cached = await env.AI_DB.prepare(
    "SELECT provider_call_id, http_status, response_ciphertext, response_iv, response_expires_at_ms FROM ai_provider_calls WHERE provider_call_id = ?"
  ).bind(providerCallId).first<StoredProviderCall>();
  if (cached?.response_ciphertext && cached.response_iv && (cached.response_expires_at_ms ?? 0) > Date.now()) {
    const cachedBytes = await decryptResponse(cached.response_ciphertext, cached.response_iv, env.RESPONSE_CACHE_ENCRYPTION_KEY);
    const quota = await stub.usageQuotaForSession(generationId, sessionToken);
    return providerResponse(cachedBytes, cached.http_status, startedAt, "cache", undefined, undefined, undefined, quota, {
      providerCallId,
      pricingVersion,
      accountingStatus: "not_billable",
      costMicroUSD: 0,
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
      responseModel: null
    });
  }

  await stub.reserveProviderCall(generationId, sessionToken, providerCallId);
  let finalized = false;
  try {
    const upstreamStartedAt = performance.now();
    const upstream = await fetch(`${env.DEEPSEEK_BASE_URL.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.DEEPSEEK_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: rawBody
    });
    const upstreamDuration = performance.now() - upstreamStartedAt;
    const responseBytes = await upstream.arrayBuffer();
    const metadata = extractProviderMetadata(responseBytes, requestPayload.model, upstream.ok);
    const encrypted = await encryptResponse(responseBytes, env.RESPONSE_CACHE_ENCRYPTION_KEY);
    const now = Date.now();
    const accounting = await stub.finalizeProviderCall({
      providerCallId,
      generationId,
      operation,
      requestedModel: requestPayload.model,
      httpStatus: upstream.status,
      rawResponseBytes: responseBytes.byteLength,
      metadata,
      responseCiphertext: encrypted.ciphertext,
      responseIV: encrypted.iv,
      responseExpiresAtMs: now + providerResponseTTLMilliseconds,
      createdAtMs: now
    });
    finalized = true;
    return providerResponse(
      responseBytes,
      upstream.status,
      startedAt,
      "upstream",
      upstreamDuration,
      upstream.headers.get("Retry-After"),
      upstream.headers.get("X-Request-ID") ?? upstream.headers.get("X-Request-Id"),
      accounting.quota,
      accounting.event
    );
  } finally {
    if (!finalized) {
      await stub.releaseProviderCallReservation(providerCallId);
    }
  }
}

type ProviderMetadata = {
  model: string | null;
  responseID: string | null;
  finishReason: string | null;
  usagePresent: boolean;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  cacheHitTokens: number;
  cacheMissTokens: number;
  costMicroUSD: number;
  pricingVersion: string;
  accountingStatus: ProviderAccountingStatus;
};

export function extractProviderMetadata(bytes: ArrayBuffer, requestedModel: string, billable: boolean): ProviderMetadata {
  try {
    const envelope = JSON.parse(textDecoder.decode(bytes)) as ProviderEnvelope;
    const usagePresent = envelope.usage !== undefined;
    const usage = envelope.usage ?? {};
    const promptTokens = numeric(usage.prompt_tokens);
    const completionTokens = numeric(usage.completion_tokens);
    const cacheHitTokens = numeric(usage.prompt_cache_hit_tokens);
    const cacheMissTokens = numeric(usage.prompt_cache_miss_tokens) || promptTokens;
    const model = envelope.model ?? null;
    const costMicroUSD = billable && usagePresent && model !== null
      ? estimateCostMicroUSD(model, cacheHitTokens, cacheMissTokens, completionTokens)
      : 0;
    const accountingStatus: ProviderAccountingStatus = !billable
      ? "not_billable"
      : usagePresent && model !== null && isPricedModel(model)
        ? "accounted"
        : "accounting_error";
    return {
      model,
      responseID: envelope.id ?? null,
      finishReason: envelope.choices?.[0]?.finish_reason ?? null,
      usagePresent,
      promptTokens,
      completionTokens,
      totalTokens: numeric(usage.total_tokens) || promptTokens + completionTokens,
      cacheHitTokens,
      cacheMissTokens,
      costMicroUSD,
      pricingVersion,
      accountingStatus
    };
  } catch {
    void requestedModel;
    return {
      model: null,
      responseID: null,
      finishReason: null,
      usagePresent: false,
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
      cacheHitTokens: 0,
      cacheMissTokens: 0,
      costMicroUSD: 0,
      pricingVersion,
      accountingStatus: billable ? "accounting_error" : "not_billable"
    };
  }
}

export function estimateCostMicroUSD(model: string, cacheHitTokens: number, cacheMissTokens: number, completionTokens: number): number {
  if (!isPricedModel(model)) return 0;
  return Math.round((cacheHitTokens * 0.0028 + cacheMissTokens * 0.14 + completionTokens * 0.28));
}

function isPricedModel(model: string): boolean {
  return model.trim().toLowerCase() === "deepseek-v4-flash";
}

function parseProviderRequest(rawBody: ArrayBuffer, allowedModel: string): { model: string } {
  let payload: { model?: unknown; messages?: unknown };
  try { payload = JSON.parse(textDecoder.decode(rawBody)); } catch { throw new WorkerError(400, "invalid-argument", "Provider request body must be valid JSON."); }
  if (payload.model !== allowedModel || !Array.isArray(payload.messages) || payload.messages.length === 0) {
    throw new WorkerError(400, "invalid-argument", "Provider request is not allowed.");
  }
  return {model: payload.model};
}

async function verifyFirebaseIDToken(idToken: string, env: Env): Promise<string> {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_WEB_API_KEY)}`, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({idToken})
  });
  const payload = await response.json<{ users?: Array<{ localId?: string }> }>();
  const uid = payload.users?.[0]?.localId;
  if (!response.ok || !uid) throw new WorkerError(401, "unauthenticated", "Sign in is required.");
  return uid;
}

async function readFirestoreProfile(uid: string, env: Env): Promise<Omit<Entitlement, "uid">> {
  const accessToken = await serviceAccountAccessToken(env.FIREBASE_SERVICE_ACCOUNT_JSON);
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents/users/${encodeURIComponent(uid)}`;
  const response = await fetch(url, {headers: {Authorization: `Bearer ${accessToken}`}});
  if (response.status === 404) return {premium: false, freeGenerationsUsed: 0, freeGenerationsLimit: freeLifetimeGenerationLimit};
  if (!response.ok) throw new WorkerError(503, "unavailable", "Subscription profile is unavailable.");
  const document = await response.json<{ fields?: Record<string, { booleanValue?: boolean; stringValue?: string; integerValue?: string }> }>();
  const fields = document.fields ?? {};
  const premium = fields.premium?.booleanValue === true || fields.plan?.stringValue === "premium";
  return {
    premium,
    freeGenerationsUsed: Number(fields.freeGenerationsUsed?.integerValue ?? 0) || 0,
    freeGenerationsLimit: Number(fields.freeGenerationsLimit?.integerValue ?? freeLifetimeGenerationLimit) || freeLifetimeGenerationLimit
  };
}

let cachedServiceAccountToken: { value: string; expiresAtMs: number } | undefined;
async function serviceAccountAccessToken(secret: string): Promise<string> {
  if (cachedServiceAccountToken && cachedServiceAccountToken.expiresAtMs > Date.now() + 60_000) return cachedServiceAccountToken.value;
  const account = JSON.parse(secret) as { client_email: string; private_key: string; token_uri?: string };
  const tokenURL = account.token_uri ?? "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1_000);
  const assertion = await signServiceAccountJWT(account.client_email, account.private_key, tokenURL, now);
  const response = await fetch(tokenURL, {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion})
  });
  const payload = await response.json<{ access_token?: string; expires_in?: number }>();
  if (!response.ok || !payload.access_token) throw new WorkerError(503, "unavailable", "Subscription profile authorization failed.");
  cachedServiceAccountToken = {value: payload.access_token, expiresAtMs: Date.now() + (payload.expires_in ?? 3600) * 1_000};
  return payload.access_token;
}

async function signServiceAccountJWT(email: string, pem: string, audience: string, now: number): Promise<string> {
  const encode = (value: unknown) => base64URL(textEncoder.encode(JSON.stringify(value)));
  const signingInput = `${encode({alg: "RS256", typ: "JWT"})}.${encode({iss: email, scope: "https://www.googleapis.com/auth/datastore", aud: audience, iat: now, exp: now + 3600})}`;
  const binary = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", bytesToArrayBuffer(base64ToBytes(binary)), {name: "RSASSA-PKCS1-v1_5", hash: "SHA-256"}, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, textEncoder.encode(signingInput));
  return `${signingInput}.${base64URL(signature)}`;
}

async function encryptResponse(data: ArrayBuffer, secret: string): Promise<{ ciphertext: string; iv: string }> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await aesKey(secret);
  const encrypted = await crypto.subtle.encrypt({name: "AES-GCM", iv}, key, data);
  return {ciphertext: base64URL(encrypted), iv: base64URL(iv)};
}

async function decryptResponse(ciphertext: string, iv: string, secret: string): Promise<ArrayBuffer> {
  return crypto.subtle.decrypt({name: "AES-GCM", iv: bytesToArrayBuffer(base64ToBytes(iv))}, await aesKey(secret), bytesToArrayBuffer(base64ToBytes(ciphertext)));
}

async function aesKey(secret: string): Promise<CryptoKey> {
  const digest = await crypto.subtle.digest("SHA-256", textEncoder.encode(secret));
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function sessionTokenFor(generationId: string, secret: string): Promise<string> {
  const sessionSecret = requiredSessionSecret(secret);
  const key = await crypto.subtle.importKey("raw", textEncoder.encode(sessionSecret), {name: "HMAC", hash: "SHA-256"}, false, ["sign"]);
  return base64URL(await crypto.subtle.sign("HMAC", key, textEncoder.encode(generationId)));
}

function providerResponse(
  data: ArrayBuffer,
  status: number,
  startedAt: number,
  source: string,
  upstreamDuration?: number,
  retryAfter?: string | null,
  requestID?: string | null,
  usageQuota?: QuotaResponse,
  usageEvent?: UsageEventResponse
): Response {
  const headers = new Headers({"Content-Type": "application/json", "X-QuizFlash-Proxy": source});
  const timing = [`proxy;dur=${(performance.now() - startedAt).toFixed(1)}`];
  if (upstreamDuration !== undefined) timing.push(`deepseek;dur=${upstreamDuration.toFixed(1)}`);
  headers.set("Server-Timing", timing.join(", "));
  if (retryAfter) headers.set("Retry-After", retryAfter);
  if (requestID) headers.set("X-Request-ID", requestID);
  if (usageQuota) headers.set("X-QuizFlash-Usage-Quota", compactJSON(usageQuota));
  if (usageEvent) headers.set("X-QuizFlash-Usage-Event", compactJSON(usageEvent));
  return new Response(data, {status, headers});
}

function timedJSON(payload: Record<string, unknown>, startedAt: number, requestID: string): Response {
  return Response.json(payload, {headers: {
    "Server-Timing": `proxy;dur=${(performance.now() - startedAt).toFixed(1)}`,
    "X-Request-ID": requestID
  }});
}

function errorResponse(error: unknown, startedAt: number, requestID: string, route: string): Response {
  const workerError = error instanceof WorkerError ? error : new WorkerError(500, "internal", "Internal server error.");
  if (!(error instanceof WorkerError)) {
    console.error(JSON.stringify({event: "worker_request_failed", request_id: requestID, route, error_name: errorName(error)}));
  }
  const body: Record<string, unknown> = {error: {code: workerError.code, message: workerError.message}};
  if (workerError.usageQuota) {
    body.usageQuota = workerError.usageQuota;
    body.quota = workerError.usageQuota;
  }
  const headers: Record<string, string> = {
    "Server-Timing": `proxy;dur=${(performance.now() - startedAt).toFixed(1)}`,
    "X-Request-ID": requestID
  };
  if (workerError.usageQuota) headers["X-QuizFlash-Usage-Quota"] = compactJSON(workerError.usageQuota);
  return Response.json(body, {
    status: workerError.status,
    headers
  });
}

class WorkerError extends Error {
  constructor(readonly status: number, readonly code: string, message: string, readonly usageQuota?: QuotaResponse) { super(message); }
}

function bearerToken(request: Request): string {
  const value = request.headers.get("Authorization") ?? "";
  if (!value.startsWith("Bearer ")) throw new WorkerError(401, "unauthenticated", "Sign in is required.");
  return value.slice("Bearer ".length).trim();
}

function nonEmptyString(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) throw new WorkerError(400, "invalid-argument", `${name} is invalid.`);
  return value;
}

function optionalString(value: unknown, name: string, maxLength: number): string | undefined {
  if (value === undefined || value === null) return undefined;
  return nonEmptyString(value, name, maxLength);
}

function requiredSessionSecret(secret: string | undefined): string {
  if (!secret?.trim()) throw new WorkerError(503, "unavailable", "AI session configuration is unavailable.");
  return secret;
}

function errorName(error: unknown): string {
  return error instanceof Error && error.name ? error.name : "unknown";
}

function sessionRejection(status: number, code: string, message: string, usageQuota?: QuotaResponse): SessionStartResult {
  return {kind: "rejection", status, code, message, usageQuota};
}

function positiveInteger(value: unknown, name: string): number {
  const number = typeof value === "string" ? Number(value) : value;
  if (!Number.isInteger(number) || (number as number) < 1) throw new WorkerError(400, "invalid-argument", `${name} is invalid.`);
  return number as number;
}

function usageEvent(providerCallId: string, metadata: ProviderMetadata): UsageEventResponse {
  return {
    providerCallId,
    pricingVersion: metadata.pricingVersion,
    accountingStatus: metadata.accountingStatus,
    costMicroUSD: metadata.costMicroUSD,
    promptTokens: metadata.promptTokens,
    completionTokens: metadata.completionTokens,
    totalTokens: metadata.totalTokens,
    responseModel: metadata.model
  };
}

function compactJSON(value: unknown): string {
  return JSON.stringify(value);
}

function numeric(value: unknown): number { return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0; }
function monthKey(now: number): string { const date = new Date(now); return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, "0")}`; }
function base64URL(data: ArrayBuffer | Uint8Array): string { const bytes = data instanceof Uint8Array ? data : new Uint8Array(data); let text = ""; bytes.forEach((byte) => { text += String.fromCharCode(byte); }); return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, ""); }
function base64ToBytes(value: string): Uint8Array { const normalized = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "="); return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0)); }
function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer { return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer; }
