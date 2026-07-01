export type FirestoreAdminEnv = {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
  PREMIUM_MONTHLY_AI_BUDGET_MICRO_USD?: string;
};

export type FirestoreMonthlyUsage = {
  period: string;
  generatedCards: number;
  requestCount: number;
  premiumRequestCount: number;
  freeRequestCount: number;
  costMicroUSD: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  cacheHitTokens: number;
  cacheMissTokens: number;
};

export type FirestoreAccountState = {
  uid: string;
  premium: boolean;
  freeGenerationsUsed: number;
  freeGenerationsLimit: number;
  monthlyBudgetMicroUSD: number;
  monthlyUsage: FirestoreMonthlyUsage;
};

export type GenerationUsageDelta = {
  generationId: string;
  status: "succeeded" | "partial" | "failed" | "expired";
  premiumAtStart: boolean;
  validatedCards: number;
  costMicroUSD: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  cacheHitTokens: number;
  cacheMissTokens: number;
};

type FirestoreValue = {
  booleanValue?: boolean;
  integerValue?: string;
  stringValue?: string;
  timestampValue?: string;
  mapValue?: {
    fields?: Record<string, FirestoreValue>;
  };
};

type FirestoreDocument = {
  name?: string;
  fields?: Record<string, FirestoreValue>;
  updateTime?: string;
};

type FirestoreDocumentSnapshot = {
  exists: boolean;
  document: FirestoreDocument | null;
};

type FirestoreWrite = {
  update: {
    name: string;
    fields: Record<string, FirestoreValue>;
  };
  updateMask: {
    fieldPaths: string[];
  };
  currentDocument: {
    exists?: boolean;
    updateTime?: string;
  };
};

type ParsedAccountDocuments = {
  account: FirestoreAccountState;
  profile: FirestoreDocumentSnapshot;
  usage: FirestoreDocumentSnapshot;
};

const defaultFreeGenerationsLimit = 5;
const defaultPremiumMonthlyBudgetMicroUSD = 2_000_000;
const maximumCommitAttempts = 4;
const textEncoder = new TextEncoder();

export async function readFirestoreAccountState(
  uid: string,
  period: string,
  env: FirestoreAdminEnv
): Promise<FirestoreAccountState> {
  const accessToken = await serviceAccountAccessToken(env.FIREBASE_SERVICE_ACCOUNT_JSON);
  for (let attempt = 0; attempt < maximumCommitAttempts; attempt += 1) {
    const documents = await readAccountDocuments(uid, period, env, accessToken);
    const fields = missingCanonicalProfileFields(documents);
    if (Object.keys(fields).length === 0) {
      return documents.account;
    }

    const response = await commitWrites([
      updateWrite(userPath(uid, env), fields, documents.profile)
    ], env, accessToken);
    if (response.ok) {
      return documents.account;
    }
    if (response.status !== 409 && response.status !== 412) {
      throw new Error(`Firestore profile normalization failed with status ${response.status}.`);
    }
  }
  throw new Error("Firestore profile normalization conflicted too many times.");
}

export async function finalizeFirestoreGenerationUsage(
  uid: string,
  period: string,
  delta: GenerationUsageDelta,
  env: FirestoreAdminEnv
): Promise<FirestoreAccountState> {
  const accessToken = await serviceAccountAccessToken(env.FIREBASE_SERVICE_ACCOUNT_JSON);

  for (let attempt = 0; attempt < maximumCommitAttempts; attempt += 1) {
    const event = await readDocument(usageEventPath(uid, delta.generationId, env), accessToken);
    if (event.exists) {
      return (await readAccountDocuments(uid, period, env, accessToken)).account;
    }

    const documents = await readAccountDocuments(uid, period, env, accessToken);
    const nextAccount = applyingUsageDelta(documents.account, delta);
    const writes = firestoreUsageCommitWrites(documents, nextAccount, delta, env);
    const response = await commitWrites(writes, env, accessToken);

    if (response.ok) {
      return nextAccount;
    }

    if (response.status === 409 || response.status === 412) {
      continue;
    }

    throw new Error(`Firestore usage commit failed with status ${response.status}.`);
  }

  const event = await readDocument(usageEventPath(uid, delta.generationId, env), accessToken);
  if (event.exists) {
    return (await readAccountDocuments(uid, period, env, accessToken)).account;
  }
  throw new Error("Firestore usage commit conflicted too many times.");
}

export async function replaceFirestoreMonthlyUsage(
  uid: string,
  period: string,
  usage: FirestoreMonthlyUsage,
  env: FirestoreAdminEnv
): Promise<FirestoreAccountState> {
  const accessToken = await serviceAccountAccessToken(env.FIREBASE_SERVICE_ACCOUNT_JSON);

  for (let attempt = 0; attempt < maximumCommitAttempts; attempt += 1) {
    const documents = await readAccountDocuments(uid, period, env, accessToken);
    const nextAccount = {
      ...documents.account,
      monthlyUsage: normalizedMonthlyUsage(period, usage)
    };
    const now = new Date().toISOString();
    const response = await commitWrites([
      updateWrite(
        userPath(uid, env),
        {
          premium: {booleanValue: nextAccount.premium},
          freeGenerationsUsed: integerValue(nextAccount.freeGenerationsUsed),
          freeGenerationsLimit: integerValue(nextAccount.freeGenerationsLimit),
          aiMonthlyBudgetMicroUSD: integerValue(nextAccount.monthlyBudgetMicroUSD),
          aiUsage: currentUsageValue(nextAccount, undefined, now),
          updatedAt: {timestampValue: now}
        },
        documents.profile
      ),
      updateWrite(
        monthlyUsagePath(uid, period, env),
        monthlyUsageFields(nextAccount.monthlyUsage, "d1-repair", now),
        documents.usage
      )
    ], env, accessToken);

    if (response.ok) {
      return nextAccount;
    }

    if (response.status !== 409 && response.status !== 412) {
      throw new Error(`Firestore usage repair failed with status ${response.status}.`);
    }
  }

  throw new Error("Firestore usage repair conflicted too many times.");
}

export function applyingUsageDelta(
  account: FirestoreAccountState,
  delta: GenerationUsageDelta
): FirestoreAccountState {
  const consumeFreeGeneration =
    !account.premium &&
    !delta.premiumAtStart &&
    delta.validatedCards > 0 &&
    (delta.status === "succeeded" || delta.status === "partial");
  const usage = account.monthlyUsage;

  return {
    ...account,
    freeGenerationsUsed: consumeFreeGeneration
      ? account.freeGenerationsUsed + 1
      : account.freeGenerationsUsed,
    monthlyUsage: {
      ...usage,
      generatedCards: usage.generatedCards + nonNegativeInteger(delta.validatedCards),
      requestCount: usage.requestCount + 1,
      premiumRequestCount: usage.premiumRequestCount + (delta.premiumAtStart ? 1 : 0),
      freeRequestCount: usage.freeRequestCount + (delta.premiumAtStart ? 0 : 1),
      costMicroUSD: usage.costMicroUSD + nonNegativeInteger(delta.costMicroUSD),
      promptTokens: usage.promptTokens + nonNegativeInteger(delta.promptTokens),
      completionTokens: usage.completionTokens + nonNegativeInteger(delta.completionTokens),
      totalTokens: usage.totalTokens + nonNegativeInteger(delta.totalTokens),
      cacheHitTokens: usage.cacheHitTokens + nonNegativeInteger(delta.cacheHitTokens),
      cacheMissTokens: usage.cacheMissTokens + nonNegativeInteger(delta.cacheMissTokens)
    }
  };
}

export function parseFirestoreAccountState(
  uid: string,
  period: string,
  profile: FirestoreDocument | null,
  usage: FirestoreDocument | null,
  fallbackMonthlyBudgetMicroUSD = defaultPremiumMonthlyBudgetMicroUSD
): FirestoreAccountState {
  const profileFields = profile?.fields ?? {};
  const rootUsageFields = profileFields.aiUsage?.mapValue?.fields;
  const rootUsagePeriod = rootUsageFields?.period?.stringValue;
  const monthlyArchiveFields = usage?.fields ?? {};
  const usageFields = rootUsagePeriod === period && !usageFieldsAreEmpty(rootUsageFields)
    ? rootUsageFields ?? {}
    : monthlyArchiveFields;
  const premiumField = profileFields.premium?.booleanValue;

  return {
    uid,
    premium: typeof premiumField === "boolean"
      ? premiumField
      : profileFields.plan?.stringValue === "premium",
    freeGenerationsUsed: integerField(profileFields, "freeGenerationsUsed", 0),
    freeGenerationsLimit: integerField(profileFields, "freeGenerationsLimit", defaultFreeGenerationsLimit),
    monthlyBudgetMicroUSD: integerField(
      profileFields,
      "aiMonthlyBudgetMicroUSD",
      fallbackMonthlyBudgetMicroUSD
    ),
    monthlyUsage: {
      period,
      generatedCards: integerField(usageFields, "generatedCards", 0),
      requestCount: integerField(usageFields, "requestCount", 0),
      premiumRequestCount: integerField(usageFields, "premiumRequestCount", 0),
      freeRequestCount: integerField(usageFields, "freeRequestCount", 0),
      costMicroUSD: integerField(usageFields, "costMicroUSD", 0),
      promptTokens: integerField(usageFields, "promptTokens", 0),
      completionTokens: integerField(usageFields, "completionTokens", 0),
      totalTokens: integerField(usageFields, "totalTokens", 0),
      cacheHitTokens: integerField(usageFields, "cacheHitTokens", 0),
      cacheMissTokens: integerField(usageFields, "cacheMissTokens", 0)
    }
  };
}

async function readAccountDocuments(
  uid: string,
  period: string,
  env: FirestoreAdminEnv,
  accessToken: string
): Promise<ParsedAccountDocuments> {
  const [profile, usage] = await Promise.all([
    readDocument(userPath(uid, env), accessToken),
    readDocument(monthlyUsagePath(uid, period, env), accessToken)
  ]);

  return {
    account: parseFirestoreAccountState(
      uid,
      period,
      profile.document,
      usage.document,
      configuredMonthlyBudgetMicroUSD(env)
    ),
    profile,
    usage
  };
}

function firestoreUsageCommitWrites(
  documents: ParsedAccountDocuments,
  nextAccount: FirestoreAccountState,
  delta: GenerationUsageDelta,
  env: FirestoreAdminEnv
): FirestoreWrite[] {
  const now = new Date().toISOString();
  const writes: FirestoreWrite[] = [
    updateWrite(
      userPath(nextAccount.uid, env),
      {
        premium: {booleanValue: nextAccount.premium},
        freeGenerationsUsed: integerValue(nextAccount.freeGenerationsUsed),
        freeGenerationsLimit: integerValue(nextAccount.freeGenerationsLimit),
        aiMonthlyBudgetMicroUSD: integerValue(nextAccount.monthlyBudgetMicroUSD),
        aiUsage: currentUsageValue(nextAccount, delta.generationId, now),
        updatedAt: {timestampValue: now}
      },
      documents.profile
    )
  ];

  writes.push(updateWrite(
    monthlyUsagePath(nextAccount.uid, nextAccount.monthlyUsage.period, env),
    monthlyUsageFields(nextAccount.monthlyUsage, delta.generationId, now),
    documents.usage
  ));
  writes.push({
    update: {
      name: usageEventPath(nextAccount.uid, delta.generationId, env),
      fields: {
        generationId: {stringValue: delta.generationId},
        period: {stringValue: nextAccount.monthlyUsage.period},
        status: {stringValue: delta.status},
        premium: {booleanValue: delta.premiumAtStart},
        validatedCards: integerValue(delta.validatedCards),
        costMicroUSD: integerValue(delta.costMicroUSD),
        promptTokens: integerValue(delta.promptTokens),
        completionTokens: integerValue(delta.completionTokens),
        totalTokens: integerValue(delta.totalTokens),
        cacheHitTokens: integerValue(delta.cacheHitTokens),
        cacheMissTokens: integerValue(delta.cacheMissTokens),
        finalizedAt: {timestampValue: now}
      }
    },
    updateMask: {
      fieldPaths: [
        "generationId",
        "period",
        "status",
        "premium",
        "validatedCards",
        "costMicroUSD",
        "promptTokens",
        "completionTokens",
        "totalTokens",
        "cacheHitTokens",
        "cacheMissTokens",
        "finalizedAt"
      ]
    },
    currentDocument: {exists: false}
  });
  return writes;
}

function currentUsageValue(
  account: FirestoreAccountState,
  generationId: string | undefined,
  updatedAt: string
): FirestoreValue {
  const usage = account.monthlyUsage;
  const fields: Record<string, FirestoreValue> = {
    ...usageMetricFields(usage),
    budgetMicroUSD: integerValue(account.monthlyBudgetMicroUSD),
    remainingMicroUSD: integerValue(
      Math.max(0, account.monthlyBudgetMicroUSD - usage.costMicroUSD)
    ),
    updatedAt: {timestampValue: updatedAt}
  };
  if (generationId) {
    fields.lastGenerationId = {stringValue: generationId};
  }
  return {
    mapValue: {fields}
  };
}

function monthlyUsageFields(
  usage: FirestoreMonthlyUsage,
  generationId: string,
  updatedAt: string
): Record<string, FirestoreValue> {
  return {
    ...usageMetricFields(usage),
    lastGenerationId: {stringValue: generationId},
    updatedAt: {timestampValue: updatedAt}
  };
}

function usageMetricFields(usage: FirestoreMonthlyUsage): Record<string, FirestoreValue> {
  return {
    period: {stringValue: usage.period},
    generatedCards: integerValue(usage.generatedCards),
    requestCount: integerValue(usage.requestCount),
    premiumRequestCount: integerValue(usage.premiumRequestCount),
    freeRequestCount: integerValue(usage.freeRequestCount),
    costMicroUSD: integerValue(usage.costMicroUSD),
    promptTokens: integerValue(usage.promptTokens),
    completionTokens: integerValue(usage.completionTokens),
    totalTokens: integerValue(usage.totalTokens),
    cacheHitTokens: integerValue(usage.cacheHitTokens),
    cacheMissTokens: integerValue(usage.cacheMissTokens)
  };
}

function missingCanonicalProfileFields(
  documents: ParsedAccountDocuments
): Record<string, FirestoreValue> {
  const existing = documents.profile.document?.fields ?? {};
  const fields: Record<string, FirestoreValue> = {};
  const usageFields = existing.aiUsage?.mapValue?.fields;
  const requiredUsageFields = [
    "period",
    "generatedCards",
    "requestCount",
    "premiumRequestCount",
    "freeRequestCount",
    "costMicroUSD",
    "promptTokens",
    "completionTokens",
    "totalTokens",
    "cacheHitTokens",
    "cacheMissTokens",
    "budgetMicroUSD",
    "remainingMicroUSD"
  ];

  if (typeof existing.premium?.booleanValue !== "boolean") {
    fields.premium = {booleanValue: documents.account.premium};
  }
  if (existing.aiMonthlyBudgetMicroUSD?.integerValue === undefined) {
    fields.aiMonthlyBudgetMicroUSD = integerValue(documents.account.monthlyBudgetMicroUSD);
  }
  if (
    usageFields?.period?.stringValue !== documents.account.monthlyUsage.period ||
    requiredUsageFields.some((field) => usageFields?.[field] === undefined)
  ) {
    fields.aiUsage = currentUsageValue(documents.account, undefined, new Date().toISOString());
  }
  if (Object.keys(fields).length > 0) {
    fields.updatedAt = {timestampValue: new Date().toISOString()};
  }
  return fields;
}

function updateWrite(
  name: string,
  fields: Record<string, FirestoreValue>,
  snapshot: FirestoreDocumentSnapshot
): FirestoreWrite {
  return {
    update: {name, fields},
    updateMask: {fieldPaths: Object.keys(fields)},
    currentDocument: snapshot.exists && snapshot.document?.updateTime
      ? {updateTime: snapshot.document.updateTime}
      : {exists: false}
  };
}

async function commitWrites(
  writes: FirestoreWrite[],
  env: FirestoreAdminEnv,
  accessToken: string
): Promise<Response> {
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents:commit`;
  return fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({writes})
  });
}

async function readDocument(name: string, accessToken: string): Promise<FirestoreDocumentSnapshot> {
  const response = await fetch(`https://firestore.googleapis.com/v1/${name}`, {
    headers: {Authorization: `Bearer ${accessToken}`}
  });
  if (response.status === 404) {
    return {exists: false, document: null};
  }
  if (!response.ok) {
    throw new Error(`Firestore document read failed with status ${response.status}.`);
  }
  return {
    exists: true,
    document: await response.json<FirestoreDocument>()
  };
}

function userPath(uid: string, env: FirestoreAdminEnv): string {
  return documentPath(env, `users/${encodeURIComponent(uid)}`);
}

function monthlyUsagePath(uid: string, period: string, env: FirestoreAdminEnv): string {
  return documentPath(env, `users/${encodeURIComponent(uid)}/usage/${encodeURIComponent(period)}`);
}

function usageEventPath(uid: string, generationId: string, env: FirestoreAdminEnv): string {
  return documentPath(env, `users/${encodeURIComponent(uid)}/usageEvents/${encodeURIComponent(generationId)}`);
}

function documentPath(env: FirestoreAdminEnv, suffix: string): string {
  return `projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents/${suffix}`;
}

function integerField(
  fields: Record<string, FirestoreValue>,
  field: string,
  fallback: number
): number {
  const parsed = Number(fields[field]?.integerValue);
  return Number.isFinite(parsed) ? nonNegativeInteger(parsed) : fallback;
}

function integerValue(value: number): FirestoreValue {
  return {integerValue: String(nonNegativeInteger(value))};
}

function nonNegativeInteger(value: number): number {
  return Math.max(0, Math.trunc(Number.isFinite(value) ? value : 0));
}

function usageFieldsAreEmpty(fields: Record<string, FirestoreValue> | undefined): boolean {
  if (!fields) return true;
  return [
    "generatedCards",
    "requestCount",
    "premiumRequestCount",
    "freeRequestCount",
    "costMicroUSD",
    "promptTokens",
    "completionTokens",
    "totalTokens",
    "cacheHitTokens",
    "cacheMissTokens"
  ].every((field) => integerField(fields, field, 0) === 0);
}

function normalizedMonthlyUsage(
  period: string,
  usage: FirestoreMonthlyUsage
): FirestoreMonthlyUsage {
  return {
    period,
    generatedCards: nonNegativeInteger(usage.generatedCards),
    requestCount: nonNegativeInteger(usage.requestCount),
    premiumRequestCount: nonNegativeInteger(usage.premiumRequestCount),
    freeRequestCount: nonNegativeInteger(usage.freeRequestCount),
    costMicroUSD: nonNegativeInteger(usage.costMicroUSD),
    promptTokens: nonNegativeInteger(usage.promptTokens),
    completionTokens: nonNegativeInteger(usage.completionTokens),
    totalTokens: nonNegativeInteger(usage.totalTokens),
    cacheHitTokens: nonNegativeInteger(usage.cacheHitTokens),
    cacheMissTokens: nonNegativeInteger(usage.cacheMissTokens)
  };
}

function configuredMonthlyBudgetMicroUSD(env: FirestoreAdminEnv): number {
  const parsed = Number(env.PREMIUM_MONTHLY_AI_BUDGET_MICRO_USD);
  return Number.isInteger(parsed) && parsed > 0
    ? parsed
    : defaultPremiumMonthlyBudgetMicroUSD;
}

let cachedServiceAccountToken: {value: string; expiresAtMs: number} | undefined;

async function serviceAccountAccessToken(secret: string): Promise<string> {
  if (cachedServiceAccountToken && cachedServiceAccountToken.expiresAtMs > Date.now() + 60_000) {
    return cachedServiceAccountToken.value;
  }

  const account = JSON.parse(secret) as {
    client_email: string;
    private_key: string;
    token_uri?: string;
  };
  const tokenURL = account.token_uri ?? "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1_000);
  const assertion = await signServiceAccountJWT(
    account.client_email,
    account.private_key,
    tokenURL,
    now
  );
  const response = await fetch(tokenURL, {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion
    })
  });
  const payload = await response.json<{access_token?: string; expires_in?: number}>();
  if (!response.ok || !payload.access_token) {
    throw new Error("Firestore service account authorization failed.");
  }

  cachedServiceAccountToken = {
    value: payload.access_token,
    expiresAtMs: Date.now() + (payload.expires_in ?? 3600) * 1_000
  };
  return payload.access_token;
}

async function signServiceAccountJWT(
  email: string,
  pem: string,
  audience: string,
  now: number
): Promise<string> {
  const encode = (value: unknown) => base64URL(textEncoder.encode(JSON.stringify(value)));
  const signingInput =
    `${encode({alg: "RS256", typ: "JWT"})}.` +
    `${encode({
      iss: email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: audience,
      iat: now,
      exp: now + 3600
    })}`;
  const binary = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    bytesToArrayBuffer(base64ToBytes(binary)),
    {name: "RSASSA-PKCS1-v1_5", hash: "SHA-256"},
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    textEncoder.encode(signingInput)
  );
  return `${signingInput}.${base64URL(signature)}`;
}

function base64URL(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let text = "";
  bytes.forEach((byte) => {
    text += String.fromCharCode(byte);
  });
  return btoa(text)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64ToBytes(value: string): Uint8Array {
  const normalized = value
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0));
}

function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}
