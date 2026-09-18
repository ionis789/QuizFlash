import {
  writeFirestoreSubscriptionState,
  type FirestoreAdminEnv,
  type VerifiedSubscriptionState
} from "./firestoreUsage";

export type BillingEnv = FirestoreAdminEnv & {
  AI_DB: D1Database;
  REVENUECAT_SECRET_API_KEY: string;
  REVENUECAT_WEBHOOK_AUTHORIZATION: string;
  REVENUECAT_WEBHOOK_SIGNING_SECRET?: string;
  REVENUECAT_SANDBOX_UIDS?: string;
};

type RevenueCatEntitlement = {
  expires_date?: string | null;
  product_identifier?: string | null;
  purchase_date?: string | null;
};

type RevenueCatSubscription = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  is_sandbox?: boolean;
  original_purchase_date?: string | null;
  purchase_date?: string | null;
  refunded_at?: string | null;
  unsubscribe_detected_at?: string | null;
};

export type RevenueCatCustomerInfo = {
  request_date_ms?: number;
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement>;
    original_app_user_id?: string | null;
    subscriptions?: Record<string, RevenueCatSubscription>;
  };
};

type RevenueCatWebhookEvent = {
  id?: unknown;
  type?: unknown;
  event_timestamp_ms?: unknown;
  app_user_id?: unknown;
  original_app_user_id?: unknown;
  aliases?: unknown;
  transferred_from?: unknown;
  transferred_to?: unknown;
};

type RevenueCatWebhookEnvelope = {
  api_version?: unknown;
  event?: RevenueCatWebhookEvent;
};

type WebhookRow = {
  status: string;
  received_at_ms: number;
};

const premiumEntitlementIdentifier = "premium";
const webhookRetryAfterMs = 15 * 60 * 1_000;
const signatureToleranceSeconds = 5 * 60;
const encoder = new TextEncoder();

export class BillingError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

export async function reconcileRevenueCatCustomer(
  uid: string,
  env: BillingEnv,
  fetcher: typeof fetch = fetch
): Promise<VerifiedSubscriptionState> {
  const apiKey = requiredSecret(env.REVENUECAT_SECRET_API_KEY, "RevenueCat API");
  const response = await fetcher(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
    {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${apiKey}`,
        "X-Platform": "ios"
      }
    }
  );
  if (!response.ok) {
    throw new BillingError(502, "billing-upstream", `RevenueCat reconciliation failed with status ${response.status}.`);
  }
  const customerInfo = await response.json<RevenueCatCustomerInfo>();
  const state = subscriptionStateFromRevenueCat(
    customerInfo,
    uid,
    sandboxUIDs(env.REVENUECAT_SANDBOX_UIDS)
  );
  await writeFirestoreSubscriptionState(uid, state, env);
  return state;
}

export function subscriptionStateFromRevenueCat(
  customerInfo: RevenueCatCustomerInfo,
  uid: string,
  allowedSandboxUIDs: ReadonlySet<string>
): VerifiedSubscriptionState {
  const checkedAtMs = positiveTimestamp(customerInfo.request_date_ms) ?? Date.now();
  const subscriber = customerInfo.subscriber;
  const entitlement = subscriber?.entitlements?.[premiumEntitlementIdentifier];
  const productIdentifier = nonEmpty(entitlement?.product_identifier);
  const subscription = productIdentifier
    ? subscriber?.subscriptions?.[productIdentifier]
    : undefined;
  const expiresAtMs = dateMilliseconds(entitlement?.expires_date ?? subscription?.expires_date);
  const gracePeriodExpiresAtMs = dateMilliseconds(subscription?.grace_period_expires_date);
  const effectiveExpiresAtMs = Math.max(expiresAtMs ?? 0, gracePeriodExpiresAtMs ?? 0) || null;
  const active = entitlement !== undefined
    && (effectiveExpiresAtMs === null || effectiveExpiresAtMs > checkedAtMs)
    && subscription?.refunded_at == null;
  const environment = subscription === undefined
    ? "unknown"
    : subscription.is_sandbox === true ? "sandbox" : "production";
  const environmentAllowed = environment === "production"
    || (environment === "sandbox" && allowedSandboxUIDs.has(uid));

  return {
    premium: active && environmentAllowed,
    entitlementIdentifier: premiumEntitlementIdentifier,
    productIdentifier,
    environment,
    expiresAtMs: effectiveExpiresAtMs,
    willRenew: active && subscription?.unsubscribe_detected_at == null && subscription?.refunded_at == null,
    originalPurchaseAtMs: dateMilliseconds(subscription?.original_purchase_date),
    latestPurchaseAtMs: dateMilliseconds(entitlement?.purchase_date ?? subscription?.purchase_date),
    revenueCatOriginalAppUserID: nonEmpty(subscriber?.original_app_user_id),
    verifiedAtMs: checkedAtMs
  };
}

export async function authenticateRevenueCatWebhook(
  request: Request,
  rawBody: string,
  env: BillingEnv,
  nowSeconds = Math.floor(Date.now() / 1_000)
): Promise<void> {
  const expectedAuthorization = requiredSecret(
    env.REVENUECAT_WEBHOOK_AUTHORIZATION,
    "RevenueCat webhook"
  );
  const receivedAuthorization = request.headers.get("Authorization") ?? "";
  if (!(await secureStringEqual(receivedAuthorization, expectedAuthorization))) {
    throw new BillingError(401, "unauthenticated", "Webhook authentication failed.");
  }

  const signingSecret = env.REVENUECAT_WEBHOOK_SIGNING_SECRET?.trim();
  if (!signingSecret) return;
  const signatureHeader = request.headers.get("X-RevenueCat-Webhook-Signature");
  if (!signatureHeader || !(await validWebhookSignature(rawBody, signatureHeader, signingSecret, nowSeconds))) {
    throw new BillingError(401, "unauthenticated", "Webhook signature verification failed.");
  }
}

export async function acceptRevenueCatWebhook(
  request: Request,
  env: BillingEnv,
  context: ExecutionContext
): Promise<Record<string, unknown>> {
  const rawBody = await request.text();
  await authenticateRevenueCatWebhook(request, rawBody, env);
  const envelope = parseWebhookEnvelope(rawBody);
  const event = envelope.event as RevenueCatWebhookEvent;
  const eventID = requiredEventString(event.id, "id");
  const eventType = requiredEventString(event.type, "type");
  const eventTimestampMs = requiredEventTimestamp(event.event_timestamp_ms);
  const claimed = await claimWebhookEvent(eventID, eventType, eventTimestampMs, rawBody, env);
  if (claimed) {
    context.waitUntil(processStoredWebhookEvent(eventID, envelope, env));
  }
  return {received: true, duplicate: !claimed};
}

export async function retryFailedRevenueCatWebhooks(env: BillingEnv): Promise<void> {
  const cutoff = Date.now() - webhookRetryAfterMs;
  const rows = await env.AI_DB.prepare(
    `SELECT event_id AS "eventID", payload_json AS "payloadJSON"
     FROM billing_webhook_events
     WHERE status = 'failed' OR (status = 'processing' AND received_at_ms <= ?)
     ORDER BY received_at_ms ASC
     LIMIT 20`
  ).bind(cutoff).all<{eventID: string; payloadJSON: string}>();
  for (const row of rows.results ?? []) {
    try {
      const envelope = parseWebhookEnvelope(row.payloadJSON);
      await env.AI_DB.prepare(
        "UPDATE billing_webhook_events SET status = 'processing', attempts = attempts + 1, last_error = NULL WHERE event_id = ?"
      ).bind(row.eventID).run();
      await processStoredWebhookEvent(row.eventID, envelope, env);
    } catch (error) {
      console.error(JSON.stringify({event: "billing_webhook_retry_failed", event_id: row.eventID, error_name: errorName(error)}));
    }
  }
}

export function webhookFirebaseUIDs(envelope: RevenueCatWebhookEnvelope): string[] {
  const event = envelope.event ?? {};
  const values = [
    event.app_user_id,
    event.original_app_user_id,
    ...stringArray(event.aliases),
    ...stringArray(event.transferred_from),
    ...stringArray(event.transferred_to)
  ];
  return [...new Set(values.filter(firebaseUID))] as string[];
}

async function processStoredWebhookEvent(
  eventID: string,
  envelope: RevenueCatWebhookEnvelope,
  env: BillingEnv
): Promise<void> {
  try {
    const uids = webhookFirebaseUIDs(envelope);
    for (const uid of uids) {
      await reconcileRevenueCatCustomer(uid, env);
    }
    await env.AI_DB.prepare(
      "UPDATE billing_webhook_events SET status = 'processed', processed_at_ms = ?, last_error = NULL WHERE event_id = ?"
    ).bind(Date.now(), eventID).run();
  } catch (error) {
    await env.AI_DB.prepare(
      "UPDATE billing_webhook_events SET status = 'failed', last_error = ? WHERE event_id = ?"
    ).bind(errorName(error), eventID).run();
    throw error;
  }
}

async function claimWebhookEvent(
  eventID: string,
  eventType: string,
  eventTimestampMs: number,
  payloadJSON: string,
  env: BillingEnv
): Promise<boolean> {
  const now = Date.now();
  const inserted = await env.AI_DB.prepare(
    `INSERT OR IGNORE INTO billing_webhook_events (
      event_id, event_type, event_timestamp_ms, status, payload_json, attempts, received_at_ms
    ) VALUES (?, ?, ?, 'processing', ?, 1, ?)`
  ).bind(eventID, eventType, eventTimestampMs, payloadJSON, now).run();
  if ((inserted.meta.changes ?? 0) > 0) return true;

  const existing = await env.AI_DB.prepare(
    "SELECT status, received_at_ms FROM billing_webhook_events WHERE event_id = ?"
  ).bind(eventID).first<WebhookRow>();
  if (existing?.status !== "failed" && !(existing?.status === "processing" && existing.received_at_ms <= now - webhookRetryAfterMs)) {
    return false;
  }
  const updated = await env.AI_DB.prepare(
    `UPDATE billing_webhook_events
     SET status = 'processing', payload_json = ?, attempts = attempts + 1, received_at_ms = ?, last_error = NULL
     WHERE event_id = ? AND status != 'processed'`
  ).bind(payloadJSON, now, eventID).run();
  return (updated.meta.changes ?? 0) > 0;
}

function parseWebhookEnvelope(rawBody: string): RevenueCatWebhookEnvelope {
  let envelope: RevenueCatWebhookEnvelope;
  try {
    envelope = JSON.parse(rawBody) as RevenueCatWebhookEnvelope;
  } catch {
    throw new BillingError(400, "invalid-argument", "Webhook body must be valid JSON.");
  }
  if (envelope.api_version !== "1.0" || !envelope.event) {
    throw new BillingError(400, "invalid-argument", "Webhook payload is invalid.");
  }
  return envelope;
}

async function validWebhookSignature(
  rawBody: string,
  header: string,
  secret: string,
  nowSeconds: number
): Promise<boolean> {
  const parts = new Map(header.split(",").map((part) => {
    const separator = part.indexOf("=");
    return separator > 0
      ? [part.slice(0, separator).trim(), part.slice(separator + 1).trim()]
      : [part.trim(), ""];
  }));
  const timestampText = parts.get("t");
  const signatureHex = parts.get("v1");
  const timestamp = Number(timestampText);
  if (!timestampText || !signatureHex || !Number.isInteger(timestamp)) return false;
  if (Math.abs(nowSeconds - timestamp) > signatureToleranceSeconds) return false;
  const signature = hexBytes(signatureHex);
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    {name: "HMAC", hash: "SHA-256"},
    false,
    ["verify"]
  );
  return crypto.subtle.verify(
    "HMAC",
    key,
    bytesToArrayBuffer(signature),
    encoder.encode(`${timestampText}.${rawBody}`)
  );
}

async function secureStringEqual(received: string, expected: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(expected),
    {name: "HMAC", hash: "SHA-256"},
    false,
    ["sign", "verify"]
  );
  const expectedSignature = await crypto.subtle.sign("HMAC", key, encoder.encode(expected));
  return crypto.subtle.verify("HMAC", key, expectedSignature, encoder.encode(received));
}

function sandboxUIDs(value: string | undefined): Set<string> {
  return new Set((value ?? "").split(",").map((item) => item.trim()).filter(Boolean));
}

function requiredSecret(value: string | undefined, name: string): string {
  if (!value?.trim()) throw new BillingError(503, "billing-unavailable", `${name} configuration is unavailable.`);
  return value.trim();
}

function requiredEventString(value: unknown, name: string): string {
  if (typeof value !== "string" || !value.trim() || value.length > 255) {
    throw new BillingError(400, "invalid-argument", `Webhook ${name} is invalid.`);
  }
  return value;
}

function requiredEventTimestamp(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new BillingError(400, "invalid-argument", "Webhook event_timestamp_ms is invalid.");
  }
  return value;
}

function stringArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function firebaseUID(value: unknown): value is string {
  return typeof value === "string"
    && /^[A-Za-z0-9_-]{1,128}$/.test(value)
    && !value.startsWith("$RCAnonymousID");
}

function nonEmpty(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function dateMilliseconds(value: unknown): number | null {
  if (typeof value !== "string" || !value) return null;
  const milliseconds = Date.parse(value);
  return Number.isFinite(milliseconds) ? milliseconds : null;
}

function positiveTimestamp(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : null;
}

function hexBytes(value: string): Uint8Array | null {
  if (!/^[0-9a-fA-F]{64}$/.test(value)) return null;
  return Uint8Array.from(value.match(/.{2}/g) ?? [], (byte) => Number.parseInt(byte, 16));
}

function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

function errorName(error: unknown): string {
  return error instanceof Error && error.name ? error.name : "unknown";
}
