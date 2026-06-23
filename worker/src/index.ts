import { DurableObject } from "cloudflare:workers";

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
};

type SessionStart = {
  idempotencyKey: string;
  targetCards: number;
  entitlement: Entitlement;
  monthlyBudgetMicroUSD: number;
};

type SessionState = {
  generationId: string;
  idempotencyKey: string;
  sessionToken: string;
  premium: boolean;
  targetCards: number;
  expiresAtMs: number;
};

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

const freeLifetimeGenerationLimit = 5;
const freeMaxCardsPerGeneration = 30;
const premiumMaxCardsPerGeneration = 100;
const activeSessionTTLMilliseconds = 20 * 60 * 1_000;
const providerResponseTTLMilliseconds = 15 * 60 * 1_000;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export class UserGenerationCoordinator extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  async start(input: SessionStart): Promise<Record<string, unknown>> {
    const now = Date.now();
    const active = await this.ctx.storage.get<SessionState>("active");
    if (active && active.expiresAtMs > now && active.idempotencyKey !== input.idempotencyKey) {
      throw new WorkerError(429, "resource-exhausted", "Another AI generation is already running.");
    }

    const existing = await this.env.AI_DB.prepare(
      "SELECT id, status, premium, target_cards FROM ai_generations WHERE uid = ? AND idempotency_key = ?"
    ).bind(input.entitlement.uid, input.idempotencyKey).first<{ id: string; status: string; premium: number; target_cards: number }>();

    if (existing?.status === "succeeded" || existing?.status === "partial") {
      return this.sessionResponse(existing.id, input.entitlement.uid, existing.premium === 1, existing.target_cards, now);
    }

    const quota = await this.ensureFreeQuota(input.entitlement, now);
    if (!input.entitlement.premium && quota.used >= quota.limit) {
      throw new WorkerError(429, "resource-exhausted", "Free AI generation limit reached.");
    }

    const maxCards = input.entitlement.premium ? premiumMaxCardsPerGeneration : freeMaxCardsPerGeneration;
    if (input.targetCards > maxCards) {
      throw new WorkerError(412, "failed-precondition", `This plan allows up to ${maxCards} cards per generation.`);
    }

    const period = monthKey(now);
    const monthly = await this.env.AI_DB.prepare(
      "SELECT cost_micro_usd FROM ai_monthly_usage WHERE uid = ? AND period = ?"
    ).bind(input.entitlement.uid, period).first<{ cost_micro_usd: number }>();
    if (input.entitlement.premium && (monthly?.cost_micro_usd ?? 0) >= input.monthlyBudgetMicroUSD) {
      throw new WorkerError(429, "resource-exhausted", "Monthly AI budget reached.");
    }

    const generationId = existing?.id ?? crypto.randomUUID();
    if (!existing) {
      await this.env.AI_DB.prepare(
        `INSERT INTO ai_generations (
          id, uid, idempotency_key, status, premium, target_cards, created_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, 'reserved', ?, ?, ?, ?)`
      ).bind(
        generationId,
        input.entitlement.uid,
        input.idempotencyKey,
        input.entitlement.premium ? 1 : 0,
        input.targetCards,
        now,
        now
      ).run();
    }

    const response = await this.sessionResponse(generationId, input.entitlement.uid, input.entitlement.premium, input.targetCards, now);
    await this.ctx.storage.put("active", {
      generationId,
      idempotencyKey: input.idempotencyKey,
      sessionToken: response.sessionToken as string,
      premium: input.entitlement.premium,
      targetCards: input.targetCards,
      expiresAtMs: now + activeSessionTTLMilliseconds
    } satisfies SessionState);
    await this.ctx.storage.setAlarm(now + activeSessionTTLMilliseconds);
    return response;
  }

  async authorize(generationId: string, sessionToken: string): Promise<SessionState> {
    const active = await this.ctx.storage.get<SessionState>("active");
    if (!active || active.generationId !== generationId || active.expiresAtMs <= Date.now() || active.sessionToken !== sessionToken) {
      throw new WorkerError(401, "unauthenticated", "AI generation session is invalid or expired.");
    }
    return active;
  }

  async finish(generationId: string, sessionToken: string, validatedCards: number): Promise<Record<string, unknown>> {
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

  async fail(generationId: string, sessionToken: string): Promise<void> {
    await this.authorize(generationId, sessionToken);
    const now = Date.now();
    await this.env.AI_DB.prepare(
      "UPDATE ai_generations SET status = 'failed', updated_at_ms = ?, completed_at_ms = ? WHERE id = ? AND status = 'reserved'"
    ).bind(now, now, generationId).run();
    await this.clearActive(generationId);
  }

  async entitlement(entitlement: Entitlement): Promise<Record<string, unknown>> {
    await this.ensureFreeQuota(entitlement, Date.now());
    return this.entitlementResponse(entitlement.uid, entitlement.premium);
  }

  async alarm(): Promise<void> {
    const active = await this.ctx.storage.get<SessionState>("active");
    if (active && active.expiresAtMs <= Date.now()) {
      await this.env.AI_DB.prepare(
        "UPDATE ai_generations SET status = 'expired', updated_at_ms = ? WHERE id = ? AND status = 'reserved'"
      ).bind(Date.now(), active.generationId).run();
      await this.clearActive(active.generationId);
    }
  }

  private async sessionResponse(generationId: string, uid: string, premium: boolean, targetCards: number, now: number): Promise<Record<string, unknown>> {
    const sessionToken = await sessionTokenFor(generationId, this.env.RESPONSE_CACHE_ENCRYPTION_KEY);
    return {
      generationId,
      sessionToken,
      targetCards,
      expiresAt: new Date(now + activeSessionTTLMilliseconds).toISOString(),
      quota: await this.entitlementResponse(uid, premium)
    };
  }

  private async entitlementResponse(uid: string, premium: boolean): Promise<Record<string, unknown>> {
    const quota = await this.env.AI_DB.prepare(
      "SELECT used_generations, limit_generations FROM ai_free_quota WHERE uid = ?"
    ).bind(uid).first<{ used_generations: number; limit_generations: number }>();
    const monthly = await this.env.AI_DB.prepare(
      "SELECT cost_micro_usd FROM ai_monthly_usage WHERE uid = ? AND period = ?"
    ).bind(uid, monthKey(Date.now())).first<{ cost_micro_usd: number }>();
    return {
      premium,
      freeGenerationsUsed: premium ? null : quota?.used_generations ?? 0,
      freeGenerationsLimit: premium ? null : quota?.limit_generations ?? freeLifetimeGenerationLimit,
      monthlyCostMicroUSD: monthly?.cost_micro_usd ?? 0
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
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const startedAt = performance.now();
    try {
      const url = new URL(request.url);
      if (request.method === "POST" && url.pathname === "/v1/generations/start") {
        return timedJSON(await startGeneration(request, env), startedAt);
      }
      if (request.method === "POST" && url.pathname === "/v1/generations/finish") {
        return timedJSON(await finishGeneration(request, env, false), startedAt);
      }
      if (request.method === "POST" && url.pathname === "/v1/generations/fail") {
        return timedJSON(await finishGeneration(request, env, true), startedAt);
      }
      if (request.method === "GET" && url.pathname === "/v1/entitlements") {
        return timedJSON(await readEntitlement(request, env), startedAt);
      }
      if (request.method === "POST" && url.pathname === "/v1/chat/completions") {
        return proxyCompletion(request, env, startedAt);
      }
      if (request.method === "GET" && url.pathname === "/health") return Response.json({ok: true});
      throw new WorkerError(404, "not-found", "Endpoint not found.");
    } catch (error) {
      return errorResponse(error, startedAt);
    }
  },
  async scheduled(_: ScheduledController, env: Env): Promise<void> {
    await env.AI_DB.prepare(
      "DELETE FROM ai_provider_calls WHERE response_expires_at_ms IS NOT NULL AND response_expires_at_ms <= ?"
    ).bind(Date.now()).run();
  }
} satisfies ExportedHandler<Env>;

async function startGeneration(request: Request, env: Env): Promise<Record<string, unknown>> {
  const idToken = bearerToken(request);
  const uid = await verifyFirebaseIDToken(idToken, env);
  const payload = await request.json<StartRequest>();
  const targetCards = positiveInteger(payload.targetCards, "targetCards");
  const idempotencyKey = nonEmptyString(payload.idempotencyKey, "idempotencyKey", 128);
  const profile = await readFirestoreProfile(uid, env);
  const entitlement: Entitlement = {
    uid,
    premium: profile.premium,
    freeGenerationsUsed: profile.freeGenerationsUsed,
    freeGenerationsLimit: profile.freeGenerationsLimit
  };
  const stub = env.USER_GENERATION.getByName(uid);
  return stub.start({
    idempotencyKey,
    targetCards,
    entitlement,
    monthlyBudgetMicroUSD: positiveInteger(env.PREMIUM_MONTHLY_AI_BUDGET_MICRO_USD, "PREMIUM_MONTHLY_AI_BUDGET_MICRO_USD")
  });
}

async function finishGeneration(request: Request, env: Env, failed: boolean): Promise<Record<string, unknown>> {
  const payload = await request.json<Record<string, unknown>>();
  const generationId = nonEmptyString(payload.generationId, "generationId", 128);
  const sessionToken = nonEmptyString(payload.sessionToken, "sessionToken", 256);
  const stub = env.USER_GENERATION.getByName(nonEmptyString(request.headers.get("X-QuizFlash-UID"), "X-QuizFlash-UID", 128));
  if (failed) {
    await stub.fail(generationId, sessionToken);
    return {status: "failed"};
  }
  return stub.finish(generationId, sessionToken, Math.max(0, Number(payload.validatedCards) || 0));
}

async function readEntitlement(request: Request, env: Env): Promise<Record<string, unknown>> {
  const uid = await verifyFirebaseIDToken(bearerToken(request), env);
  const profile = await readFirestoreProfile(uid, env);
  return env.USER_GENERATION.getByName(uid).entitlement({
    uid,
    premium: profile.premium,
    freeGenerationsUsed: profile.freeGenerationsUsed,
    freeGenerationsLimit: profile.freeGenerationsLimit
  });
}

async function proxyCompletion(request: Request, env: Env, startedAt: number): Promise<Response> {
  const generationId = nonEmptyString(request.headers.get("X-QuizFlash-Generation-ID"), "X-QuizFlash-Generation-ID", 128);
  const sessionToken = nonEmptyString(request.headers.get("X-QuizFlash-Session"), "X-QuizFlash-Session", 256);
  const providerCallId = nonEmptyString(request.headers.get("X-QuizFlash-Provider-Call-ID"), "X-QuizFlash-Provider-Call-ID", 128);
  const operation = request.headers.get("X-QuizFlash-Operation") === "title" ? "title" : "cards";
  const uid = nonEmptyString(request.headers.get("X-QuizFlash-UID"), "X-QuizFlash-UID", 128);
  const stub = env.USER_GENERATION.getByName(uid);
  const active = await stub.authorize(generationId, sessionToken);
  const rawBody = await request.arrayBuffer();
  const requestPayload = parseProviderRequest(rawBody, env.DEEPSEEK_MODEL);
  const cached = await env.AI_DB.prepare(
    "SELECT provider_call_id, http_status, response_ciphertext, response_iv, response_expires_at_ms FROM ai_provider_calls WHERE provider_call_id = ?"
  ).bind(providerCallId).first<StoredProviderCall>();
  if (cached?.response_ciphertext && cached.response_iv && (cached.response_expires_at_ms ?? 0) > Date.now()) {
    const cachedBytes = await decryptResponse(cached.response_ciphertext, cached.response_iv, env.RESPONSE_CACHE_ENCRYPTION_KEY);
    return providerResponse(cachedBytes, cached.http_status, startedAt, "cache");
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
  const metadata = extractProviderMetadata(responseBytes, requestPayload.model);
  const encrypted = await encryptResponse(responseBytes, env.RESPONSE_CACHE_ENCRYPTION_KEY);
  const now = Date.now();
  await env.AI_DB.prepare(
    `INSERT INTO ai_provider_calls (
      provider_call_id, generation_id, operation, requested_model, response_model, provider_response_id,
      http_status, finish_reason, raw_response_bytes, prompt_tokens, completion_tokens, total_tokens,
      cache_hit_tokens, cache_miss_tokens, estimated_cost_micro_usd, response_ciphertext, response_iv,
      response_expires_at_ms, created_at_ms
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(provider_call_id) DO NOTHING`
  ).bind(
    providerCallId, generationId, operation, requestPayload.model, metadata.model, metadata.responseID,
    upstream.status, metadata.finishReason, responseBytes.byteLength, metadata.promptTokens, metadata.completionTokens,
    metadata.totalTokens, metadata.cacheHitTokens, metadata.cacheMissTokens, metadata.costMicroUSD,
    encrypted.ciphertext, encrypted.iv, now + providerResponseTTLMilliseconds, now
  ).run();
  if (upstream.ok) {
    await recordUsage(env, generationId, active.premium, metadata, now);
  }
  return providerResponse(
    responseBytes,
    upstream.status,
    startedAt,
    "upstream",
    upstreamDuration,
    upstream.headers.get("Retry-After"),
    upstream.headers.get("X-Request-ID") ?? upstream.headers.get("X-Request-Id")
  );
}

async function recordUsage(env: Env, generationId: string, premium: boolean, metadata: ProviderMetadata, now: number): Promise<void> {
  const generation = await env.AI_DB.prepare("SELECT uid FROM ai_generations WHERE id = ?").bind(generationId).first<{ uid: string }>();
  if (!generation) return;
  await env.AI_DB.batch([
    env.AI_DB.prepare(
      `UPDATE ai_generations SET
        status = 'running', total_prompt_tokens = total_prompt_tokens + ?,
        total_completion_tokens = total_completion_tokens + ?, total_tokens = total_tokens + ?,
        total_cache_hit_tokens = total_cache_hit_tokens + ?, total_cache_miss_tokens = total_cache_miss_tokens + ?,
        cost_micro_usd = cost_micro_usd + ?, updated_at_ms = ? WHERE id = ?`
    ).bind(metadata.promptTokens, metadata.completionTokens, metadata.totalTokens, metadata.cacheHitTokens, metadata.cacheMissTokens, metadata.costMicroUSD, now, generationId),
    env.AI_DB.prepare(
      `INSERT INTO ai_monthly_usage (uid, period, generated_cards, request_count, cost_micro_usd, updated_at_ms)
       VALUES (?, ?, 0, 0, ?, ?)
       ON CONFLICT(uid, period) DO UPDATE SET
         cost_micro_usd = cost_micro_usd + excluded.cost_micro_usd,
         updated_at_ms = excluded.updated_at_ms`
    ).bind(generation.uid, monthKey(now), metadata.costMicroUSD, now)
  ]);
  void premium;
}

type ProviderMetadata = {
  model: string | null;
  responseID: string | null;
  finishReason: string | null;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  cacheHitTokens: number;
  cacheMissTokens: number;
  costMicroUSD: number;
};

function extractProviderMetadata(bytes: ArrayBuffer, requestedModel: string): ProviderMetadata {
  try {
    const envelope = JSON.parse(textDecoder.decode(bytes)) as ProviderEnvelope;
    const usage = envelope.usage ?? {};
    const promptTokens = numeric(usage.prompt_tokens);
    const completionTokens = numeric(usage.completion_tokens);
    const cacheHitTokens = numeric(usage.prompt_cache_hit_tokens);
    const cacheMissTokens = numeric(usage.prompt_cache_miss_tokens) || promptTokens;
    const model = envelope.model ?? null;
    return {
      model,
      responseID: envelope.id ?? null,
      finishReason: envelope.choices?.[0]?.finish_reason ?? null,
      promptTokens,
      completionTokens,
      totalTokens: numeric(usage.total_tokens) || promptTokens + completionTokens,
      cacheHitTokens,
      cacheMissTokens,
      costMicroUSD: estimateCostMicroUSD(model ?? requestedModel, cacheHitTokens, cacheMissTokens, completionTokens)
    };
  } catch {
    return {model: null, responseID: null, finishReason: null, promptTokens: 0, completionTokens: 0, totalTokens: 0, cacheHitTokens: 0, cacheMissTokens: 0, costMicroUSD: 0};
  }
}

export function estimateCostMicroUSD(model: string, cacheHitTokens: number, cacheMissTokens: number, completionTokens: number): number {
  if (model.trim().toLowerCase() !== "deepseek-v4-flash") return 0;
  return Math.round((cacheHitTokens * 0.0028 + cacheMissTokens * 0.14 + completionTokens * 0.28));
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
  const key = await crypto.subtle.importKey("raw", textEncoder.encode(secret), {name: "HMAC", hash: "SHA-256"}, false, ["sign"]);
  return base64URL(await crypto.subtle.sign("HMAC", key, textEncoder.encode(generationId)));
}

function providerResponse(
  data: ArrayBuffer,
  status: number,
  startedAt: number,
  source: string,
  upstreamDuration?: number,
  retryAfter?: string | null,
  requestID?: string | null
): Response {
  const headers = new Headers({"Content-Type": "application/json", "X-QuizFlash-Proxy": source});
  const timing = [`proxy;dur=${(performance.now() - startedAt).toFixed(1)}`];
  if (upstreamDuration !== undefined) timing.push(`deepseek;dur=${upstreamDuration.toFixed(1)}`);
  headers.set("Server-Timing", timing.join(", "));
  if (retryAfter) headers.set("Retry-After", retryAfter);
  if (requestID) headers.set("X-Request-ID", requestID);
  return new Response(data, {status, headers});
}

function timedJSON(payload: Record<string, unknown>, startedAt: number): Response {
  return Response.json(payload, {headers: {"Server-Timing": `proxy;dur=${(performance.now() - startedAt).toFixed(1)}`}});
}

function errorResponse(error: unknown, startedAt: number): Response {
  const workerError = error instanceof WorkerError ? error : new WorkerError(500, "internal", "Internal server error.");
  return Response.json({error: {code: workerError.code, message: workerError.message}}, {
    status: workerError.status,
    headers: {"Server-Timing": `proxy;dur=${(performance.now() - startedAt).toFixed(1)}`}
  });
}

class WorkerError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
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

function positiveInteger(value: unknown, name: string): number {
  const number = typeof value === "string" ? Number(value) : value;
  if (!Number.isInteger(number) || (number as number) < 1) throw new WorkerError(400, "invalid-argument", `${name} is invalid.`);
  return number as number;
}

function numeric(value: unknown): number { return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0; }
function monthKey(now: number): string { const date = new Date(now); return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, "0")}`; }
function base64URL(data: ArrayBuffer | Uint8Array): string { const bytes = data instanceof Uint8Array ? data : new Uint8Array(data); let text = ""; bytes.forEach((byte) => { text += String.fromCharCode(byte); }); return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, ""); }
function base64ToBytes(value: string): Uint8Array { const normalized = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "="); return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0)); }
function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer { return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer; }
