import { DurableObject } from "cloudflare:workers";
import {
  finalizeFirestoreGenerationUsage,
  readFirestoreAccountState,
  type FirestoreAccountState
} from "./firestoreUsage";
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

type StartRequest = {
  idempotencyKey?: unknown;
  targetCards?: unknown;
  knownPromptVersion?: unknown;
};

type SessionStart = {
  idempotencyKey: string;
  targetCards: number;
  uid: string;
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

type UsageGenerationRow = {
  generationId: string;
  status: string;
  premium: number;
  targetCards: number;
  validatedCards: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  cacheHitTokens: number;
  cacheMissTokens: number;
  costMicroUSD: number;
  createdAtMs: number;
  completedAtMs: number | null;
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
  event: UsageEventResponse;
};

type GenerationAccountingRow = {
  uid: string;
  premium: number;
  cost_micro_usd: number;
  total_prompt_tokens: number;
  total_completion_tokens: number;
  total_tokens: number;
  total_cache_hit_tokens: number;
  total_cache_miss_tokens: number;
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

const freeMaxCardsPerGeneration = 30;
const premiumMaxCardsPerGeneration = 100;
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
    const account = await readFirestoreAccountState(input.uid, monthKey(now), this.env);
    await this.syncD1UsageCache(account, now);

    const existing = await this.env.AI_DB.prepare(
      "SELECT id, status, premium, target_cards FROM ai_generations WHERE uid = ? AND idempotency_key = ?"
    ).bind(input.uid, input.idempotencyKey).first<{ id: string; status: string; premium: number; target_cards: number }>();

    if (existing?.status === "succeeded" || existing?.status === "partial") {
      return {
        kind: "session",
        session: await this.sessionResponse(existing.id, existing.target_cards, now, account)
      };
    }

    if (
      !account.premium &&
      account.freeGenerationsUsed >= account.freeGenerationsLimit
    ) {
      return sessionRejection(
        429,
        "resource-exhausted",
        "Free AI generation limit reached.",
        await this.entitlementResponse(account)
      );
    }

    const maxCards = account.premium ? premiumMaxCardsPerGeneration : freeMaxCardsPerGeneration;
    if (input.targetCards > maxCards) {
      return sessionRejection(412, "failed-precondition", `This plan allows up to ${maxCards} cards per generation.`);
    }

    if (account.premium) {
      const usageQuota = await this.entitlementResponse(account);
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
        input.uid,
        input.idempotencyKey,
        account.premium ? 1 : 0,
        input.targetCards,
        input.promptVersion,
        input.promptHash,
        now,
        now
      ).run();
    }

    const response = await this.sessionResponse(generationId, input.targetCards, now, account);
    await this.ctx.storage.put("active", {
      generationId,
      idempotencyKey: input.idempotencyKey,
      sessionToken: response.sessionToken as string,
      uid: input.uid,
      premium: account.premium,
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
    const generation = await this.generationAccountingRow(generationId);
    if (!generation) throw new WorkerError(404, "not-found", "AI generation was not found.");
    const account = await finalizeFirestoreGenerationUsage(
      generation.uid,
      monthKey(now),
      generationUsageDelta(generationId, finalStatus, validatedCards, generation),
      this.env
    );
    await this.env.AI_DB.prepare(
      "UPDATE ai_generations SET status = ?, validated_cards = ?, updated_at_ms = ?, completed_at_ms = ? WHERE id = ?"
    ).bind(finalStatus, validatedCards, now, now, generationId).run();
    await this.syncD1UsageCache(account, now);
    await this.clearActive(generationId);
    return this.entitlementResponse(account);
  }

  async fail(generationId: string, sessionToken: string): Promise<QuotaResponse> {
    return this.enqueue(() => this.failLocked(generationId, sessionToken));
  }

  private async failLocked(generationId: string, sessionToken: string): Promise<QuotaResponse> {
    await this.authorize(generationId, sessionToken);
    const now = Date.now();
    const generation = await this.generationAccountingRow(generationId);
    if (!generation) throw new WorkerError(404, "not-found", "AI generation was not found.");
    const account = await finalizeFirestoreGenerationUsage(
      generation.uid,
      monthKey(now),
      generationUsageDelta(generationId, "failed", 0, generation),
      this.env
    );
    await this.env.AI_DB.prepare(
      "UPDATE ai_generations SET status = 'failed', updated_at_ms = ?, completed_at_ms = ? WHERE id = ? AND status IN ('reserved', 'running')"
    ).bind(now, now, generationId).run();
    await this.syncD1UsageCache(account, now);
    await this.clearActive(generationId);
    return this.entitlementResponse(account);
  }

  async entitlement(uid: string): Promise<QuotaResponse> {
    return this.enqueue(async () => {
      const now = Date.now();
      const account = await readFirestoreAccountState(uid, monthKey(now), this.env);
      await this.syncD1UsageCache(account, now);
      return this.entitlementResponse(account);
    });
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
        return {event: usageEvent(input.providerCallId, input.metadata)};
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

      if (input.metadata.accountingStatus === "accounted") {
        const cost = input.metadata.costMicroUSD;
        statements.push(
          this.env.AI_DB.prepare(
            `UPDATE ai_generations SET
              status = 'running', total_prompt_tokens = total_prompt_tokens + ?,
              total_completion_tokens = total_completion_tokens + ?, total_tokens = total_tokens + ?,
              total_cache_hit_tokens = total_cache_hit_tokens + ?, total_cache_miss_tokens = total_cache_miss_tokens + ?,
              cost_micro_usd = cost_micro_usd + ?, updated_at_ms = ? WHERE id = ?`
          ).bind(input.metadata.promptTokens, input.metadata.completionTokens, input.metadata.totalTokens, input.metadata.cacheHitTokens, input.metadata.cacheMissTokens, cost, input.createdAtMs, input.generationId)
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
      return {event: usageEvent(input.providerCallId, input.metadata)};
    });
  }

  async alarm(): Promise<void> {
    await this.enqueue(async () => {
      const active = await this.ctx.storage.get<SessionState>("active");
      if (active && active.expiresAtMs <= Date.now()) {
        const now = Date.now();
        const generation = await this.generationAccountingRow(active.generationId);
        if (generation) {
          const account = await finalizeFirestoreGenerationUsage(
            generation.uid,
            monthKey(now),
            generationUsageDelta(active.generationId, "expired", 0, generation),
            this.env
          );
          await this.syncD1UsageCache(account, now);
        }
        await this.env.AI_DB.prepare(
          "UPDATE ai_generations SET status = 'expired', updated_at_ms = ? WHERE id = ? AND status IN ('reserved', 'running')"
        ).bind(now, active.generationId).run();
        await this.clearActive(active.generationId);
      }
    });
  }

  private async sessionResponse(
    generationId: string,
    targetCards: number,
    now: number,
    account: FirestoreAccountState
  ): Promise<GenerationSessionResponse> {
    const sessionToken = await sessionTokenFor(generationId, this.env.RESPONSE_CACHE_ENCRYPTION_KEY);
    const usageQuota = await this.entitlementResponse(account);
    return {
      generationId,
      sessionToken,
      targetCards,
      expiresAt: new Date(now + activeSessionTTLMilliseconds).toISOString(),
      quota: usageQuota,
      usageQuota
    };
  }

  private async entitlementResponse(account: FirestoreAccountState): Promise<QuotaResponse> {
    const monthly = await this.env.AI_DB.prepare(
      "SELECT reserved_cost_micro_usd FROM ai_monthly_usage WHERE uid = ? AND period = ?"
    ).bind(account.uid, account.monthlyUsage.period).first<{ reserved_cost_micro_usd: number }>();
    const consumed = Math.max(0, account.monthlyUsage.costMicroUSD);
    const reserved = Math.max(0, monthly?.reserved_cost_micro_usd ?? 0);
    const limit = account.premium ? account.monthlyBudgetMicroUSD : null;
    const available = limit === null ? null : Math.max(0, limit - consumed - reserved);
    const percent = limit && limit > 0 ? Math.min(1, (consumed + reserved) / limit) : null;
    return {
      premium: account.premium,
      freeGenerationsUsed: account.premium ? null : account.freeGenerationsUsed,
      freeGenerationsLimit: account.premium ? null : account.freeGenerationsLimit,
      monthlyCostMicroUSD: consumed,
      limitMicroUSD: limit,
      consumedMicroUSD: consumed,
      reservedMicroUSD: reserved,
      availableMicroUSD: available,
      percent
    };
  }

  private async syncD1UsageCache(account: FirestoreAccountState, now: number): Promise<void> {
    await this.env.AI_DB.batch([
      this.env.AI_DB.prepare(
        `INSERT INTO ai_free_quota (uid, used_generations, limit_generations, initialized_at_ms, updated_at_ms)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(uid) DO UPDATE SET
           used_generations = excluded.used_generations,
           limit_generations = excluded.limit_generations,
           updated_at_ms = excluded.updated_at_ms`
      ).bind(
        account.uid,
        account.freeGenerationsUsed,
        account.freeGenerationsLimit,
        now,
        now
      ),
      this.env.AI_DB.prepare(
        `INSERT INTO ai_monthly_usage (
          uid, period, generated_cards, request_count, cost_micro_usd,
          reserved_cost_micro_usd, updated_at_ms
        ) VALUES (?, ?, ?, ?, ?, 0, ?)
        ON CONFLICT(uid, period) DO UPDATE SET
          generated_cards = excluded.generated_cards,
          request_count = excluded.request_count,
          cost_micro_usd = excluded.cost_micro_usd,
          updated_at_ms = excluded.updated_at_ms`
      ).bind(
        account.uid,
        account.monthlyUsage.period,
        account.monthlyUsage.generatedCards,
        account.monthlyUsage.requestCount,
        account.monthlyUsage.costMicroUSD,
        now
      )
    ]);
  }

  private async generationAccountingRow(generationId: string): Promise<GenerationAccountingRow | null> {
    return this.env.AI_DB.prepare(
      `SELECT
        uid,
        premium,
        cost_micro_usd,
        total_prompt_tokens,
        total_completion_tokens,
        total_tokens,
        total_cache_hit_tokens,
        total_cache_miss_tokens
      FROM ai_generations
      WHERE id = ?`
    ).bind(generationId).first<GenerationAccountingRow>();
  }

  private async clearActive(generationId: string): Promise<void> {
    const active = await this.ctx.storage.get<SessionState>("active");
    if (active?.generationId === generationId) {
      await this.ctx.storage.delete("active");
      await this.ctx.storage.deleteAlarm();
    }
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
      if (request.method === "GET" && url.pathname === "/v1/usage/generations") {
        return timedJSON(await readUsageGenerations(request, env), startedAt, requestID);
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
    stage = "session_reservation";
    const stub = env.USER_GENERATION.getByName(uid);
    const startResult = await stub.start({
      idempotencyKey,
      targetCards,
      uid,
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
  const usageQuota = await env.USER_GENERATION.getByName(uid).entitlement(uid);
  return {...usageQuota};
}

async function readUsageGenerations(request: Request, env: Env): Promise<Record<string, unknown>> {
  const uid = await verifyFirebaseIDToken(bearerToken(request), env);
  const rows = await env.AI_DB.prepare(
    `SELECT
      id AS "generationId",
      status,
      premium,
      target_cards AS "targetCards",
      validated_cards AS "validatedCards",
      total_prompt_tokens AS "promptTokens",
      total_completion_tokens AS "completionTokens",
      total_tokens AS "totalTokens",
      total_cache_hit_tokens AS "cacheHitTokens",
      total_cache_miss_tokens AS "cacheMissTokens",
      cost_micro_usd AS "costMicroUSD",
      created_at_ms AS "createdAtMs",
      completed_at_ms AS "completedAtMs"
    FROM ai_generations
    WHERE uid = ?
    ORDER BY created_at_ms DESC
    LIMIT 20`
  ).bind(uid).all<UsageGenerationRow>();
  return {
    generations: (rows.results ?? []).map((row) => ({
      generationId: row.generationId,
      status: row.status,
      premium: row.premium === 1,
      targetCards: Math.max(0, row.targetCards ?? 0),
      validatedCards: Math.max(0, row.validatedCards ?? 0),
      promptTokens: Math.max(0, row.promptTokens ?? 0),
      completionTokens: Math.max(0, row.completionTokens ?? 0),
      totalTokens: Math.max(0, row.totalTokens ?? 0),
      cacheHitTokens: Math.max(0, row.cacheHitTokens ?? 0),
      cacheMissTokens: Math.max(0, row.cacheMissTokens ?? 0),
      costMicroUSD: Math.max(0, row.costMicroUSD ?? 0),
      createdAtMs: Math.max(0, row.createdAtMs ?? 0),
      completedAtMs: row.completedAtMs ?? null
    }))
  };
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
    return providerResponse(cachedBytes, cached.http_status, startedAt, "cache", undefined, undefined, undefined, undefined, {
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
  return providerResponse(
    responseBytes,
    upstream.status,
    startedAt,
    "upstream",
    upstreamDuration,
    upstream.headers.get("Retry-After"),
    upstream.headers.get("X-Request-ID") ?? upstream.headers.get("X-Request-Id"),
    undefined,
    accounting.event
  );
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

function generationUsageDelta(
  generationId: string,
  status: "succeeded" | "partial" | "failed" | "expired",
  validatedCards: number,
  generation: GenerationAccountingRow
) {
  return {
    generationId,
    status,
    premiumAtStart: generation.premium === 1,
    validatedCards,
    costMicroUSD: generation.cost_micro_usd,
    promptTokens: generation.total_prompt_tokens,
    completionTokens: generation.total_completion_tokens,
    totalTokens: generation.total_tokens,
    cacheHitTokens: generation.total_cache_hit_tokens,
    cacheMissTokens: generation.total_cache_miss_tokens
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
