import {SELF, env} from "cloudflare:test";
import {describe, expect, it} from "vitest";
import {extractProviderMetadata, premiumBudgetAllowsGeneration, promptStartResponse, providerOperation, rollingBillingWindow, usageWindowForAccount, validatedCardCount, validatedCardCountForTarget} from "../src";
import {applyingUsageDelta, parseFirestoreAccountState} from "../src/firestoreUsage";
import {activePricingSelection, estimateCostMicroUSD, pricingBandAt, validatedPricingConfig, type AIPricingConfig, type PricingSelection} from "../src/pricing";
import {defaultPromptBundle, validatedPromptBundle} from "../src/promptBundle";
import {
  authenticateRevenueCatWebhook,
  subscriptionStateFromRevenueCat,
  webhookFirebaseUIDs,
  type BillingEnv
} from "../src/billing";

describe("QuizFlash AI proxy", () => {
  it("accepts a current production premium entitlement", () => {
    const state = subscriptionStateFromRevenueCat({
      request_date_ms: Date.UTC(2026, 8, 19),
      subscriber: {
        original_app_user_id: "firebase-user",
        entitlements: {
          premium: {
            product_identifier: "com.sion.QuizFlash.premium.monthly",
            expires_date: "2026-10-19T00:00:00Z",
            purchase_date: "2026-09-19T00:00:00Z"
          }
        },
        subscriptions: {
          "com.sion.QuizFlash.premium.monthly": {
            is_sandbox: false,
            expires_date: "2026-10-19T00:00:00Z",
            original_purchase_date: "2026-09-19T00:00:00Z",
            purchase_date: "2026-09-19T00:00:00Z",
            unsubscribe_detected_at: null,
            refunded_at: null
          }
        }
      }
    }, "firebase-user", new Set());

    expect(state).toMatchObject({
      premium: true,
      environment: "production",
      willRenew: true,
      productIdentifier: "com.sion.QuizFlash.premium.monthly"
    });
  });

  it("allows sandbox premium only for explicitly configured Firebase UIDs", () => {
    const customerInfo = {
      request_date_ms: Date.UTC(2026, 8, 19),
      subscriber: {
        entitlements: {
          premium: {
            product_identifier: "com.sion.QuizFlash.premium.yearly",
            expires_date: "2027-09-19T00:00:00Z"
          }
        },
        subscriptions: {
          "com.sion.QuizFlash.premium.yearly": {
            is_sandbox: true,
            expires_date: "2027-09-19T00:00:00Z"
          }
        }
      }
    };

    expect(subscriptionStateFromRevenueCat(customerInfo, "tester", new Set()).premium).toBe(false);
    expect(subscriptionStateFromRevenueCat(customerInfo, "tester", new Set(["tester"])).premium).toBe(true);
  });

  it("does not leave an expired entitlement premium", () => {
    const state = subscriptionStateFromRevenueCat({
      request_date_ms: Date.UTC(2026, 8, 19),
      subscriber: {
        entitlements: {
          premium: {
            product_identifier: "com.sion.QuizFlash.premium.monthly",
            expires_date: "2026-08-19T00:00:00Z"
          }
        },
        subscriptions: {
          "com.sion.QuizFlash.premium.monthly": {
            is_sandbox: false,
            expires_date: "2026-08-19T00:00:00Z"
          }
        }
      }
    }, "firebase-user", new Set());

    expect(state.premium).toBe(false);
  });

  it("reconciles both sides of a RevenueCat transfer and ignores anonymous IDs", () => {
    expect(webhookFirebaseUIDs({
      api_version: "1.0",
      event: {
        transferred_from: ["sourceUID", "$RCAnonymousID:ignored"],
        transferred_to: ["destinationUID"]
      }
    })).toEqual(["sourceUID", "destinationUID"]);
  });

  it("rejects a webhook with the wrong authorization value", async () => {
    const request = new Request("https://example.test/v1/billing/webhook", {
      method: "POST",
      headers: {Authorization: "Bearer wrong"}
    });
    const env = {
      REVENUECAT_WEBHOOK_AUTHORIZATION: "Bearer expected"
    } as BillingEnv;

    await expect(authenticateRevenueCatWebhook(request, "{}", env)).rejects.toMatchObject({
      status: 401,
      code: "unauthenticated"
    });
  });

  it("publishes the exact blueprint schema placeholder on final-output templates", () => {
    expect(defaultPromptBundle.version).toBe("v21");
    expect(defaultPromptBundle.templates["system.userInstructions"]).toContain("lower priority");
    expect(defaultPromptBundle.templates["user.instructions"]).toContain("{{userInstructionsJSON}}");
    expect(defaultPromptBundle.templates["blueprint.schema"]).not.toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.reduce"]).toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.repair"]).toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.supplement"]).toContain("{{supplementPlanJSON}}");
    expect(defaultPromptBundle.templates["rules.flashcard"]).toContain("complete, actionable recall question or instruction");
  });

  it("keeps blueprint planning neutral and requires coverage for every returned theme", () => {
    expect(defaultPromptBundle.templates["blueprint.system"]).toContain("Planning is coverage-neutral");
    expect(defaultPromptBundle.templates["blueprint.system"]).toContain("no durable source-domain knowledge");
    expect(defaultPromptBundle.templates["blueprint.schema"]).toContain("Every returned theme must be referenced by at least one objective");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("construct its global conceptual map before assigning objective slots");
    expect(defaultPromptBundle.templates["blueprint.reduce"]).toContain("derive themes exclusively by grouping those objectives");
    expect(defaultPromptBundle.templates["blueprint.repair"]).toContain("Do not repair by truncating a prefix or suffix");
    expect(defaultPromptBundle.templates["blueprint.supplement"]).toContain("Do not paraphrase an existing objective");
    expect(defaultPromptBundle.templates["blueprint.schema"]).toContain("the union of its objectives' source segment indexes");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("Prefer new conceptual coverage over alternate or equivalent formulations");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("objectives array length is a hard structural constraint");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("does not require one objective per segment");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("complementary atomic recall tasks");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("Never fill slots with paraphrase variants");
    expect(defaultPromptBundle.templates["blueprint.schema"]).toContain('"required":["v","t","lc","ln","th","ob"]');
    expect(defaultPromptBundle.templates["blueprint.schema"]).toContain('"minItems":3,"maxItems":3');
    expect(defaultPromptBundle.templates["blueprint.schema"]).toContain('"minItems":4,"maxItems":4');
    expect(defaultPromptBundle.templates["blueprint.schema"]).toContain("Never return keyed objects inside th or ob");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("ob must contain exactly {{targetCards}} positional arrays");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("expected answer");
    expect(defaultPromptBundle.templates["blueprint.schema"]).not.toContain('"suggested_title"');
  });

  it("accepts every supported blueprint operation and rejects unknown operations", () => {
    expect(providerOperation("blueprint_map")).toBe("blueprint_map");
    expect(providerOperation("blueprint_reduce")).toBe("blueprint_reduce");
    expect(providerOperation("blueprint_repair")).toBe("blueprint_repair");
    expect(providerOperation("title")).toBe("title");
    expect(providerOperation("cards")).toBe("cards");
    expect(() => providerOperation("unsupported")).toThrow();
  });

  it("requires finish counts to be nonnegative integers", () => {
    expect(validatedCardCount(0)).toBe(0);
    expect(validatedCardCount(30)).toBe(30);
    expect(() => validatedCardCount(-1)).toThrow();
    expect(() => validatedCardCount(1.5)).toThrow();
    expect(() => validatedCardCount("3")).toThrow();
  });

  it("rejects finish counts above the authorized target", () => {
    expect(validatedCardCountForTarget(30, 30)).toBe(30);
    expect(() => validatedCardCountForTarget(31, 30)).toThrow();
  });

  it("returns a health response without touching provider credentials", async () => {
    const response = await SELF.fetch("https://example.test/health");

    expect(response.status).toBe(200);
    expect(response.headers.get("X-Request-ID")).toMatch(/^[0-9a-f-]{36}$/);
    await expect(response.json()).resolves.toMatchObject({
      ok: true,
      pricingVersion: "deepseek-flash@2026-09-10",
      pricingModel: "deepseek-flash",
      defaultPremiumBudgetMicroUSD: 1_500_000
    });
  });

  it("rejects unauthenticated generation starts", async () => {
    const response = await SELF.fetch("https://example.test/v1/generations/start", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({idempotencyKey: "test-request", targetCards: 10})
    });

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      error: {code: "unauthenticated"}
    });
  });

  it("omits the prompt bundle when the client already has the active version", async () => {
    const promptConfig = await validatedPromptBundle(defaultPromptBundle);
    const response = promptStartResponse({generationId: "generation"}, promptConfig, promptConfig.version);

    expect(response.promptVersion).toBe(promptConfig.version);
    expect(response.promptHash).toBe(promptConfig.hash);
    expect(response.promptBundle).toBeUndefined();
  });

  it("includes the prompt bundle when the client version is missing or stale", async () => {
    const promptConfig = await validatedPromptBundle(defaultPromptBundle);
    const response = promptStartResponse({generationId: "generation"}, promptConfig, "old");

    expect(response.promptVersion).toBe(promptConfig.version);
    expect(response.promptHash).toBe(promptConfig.hash);
    expect(response.promptBundle).toEqual(promptConfig);
  });

  it("preserves usageQuota in the generation start response contract", async () => {
    const promptConfig = await validatedPromptBundle(defaultPromptBundle);
    const usageQuota = {
      premium: true,
      freeGenerationsUsed: null,
      freeGenerationsLimit: null,
      monthlyCostMicroUSD: 12_000,
      limitMicroUSD: 20_000,
      consumedMicroUSD: 12_000,
      reservedMicroUSD: 0,
      availableMicroUSD: 8_000,
      percent: 0.6,
      usageBasis: "rolling_30d",
      billingWindowKey: "r30_1782323063585",
      billingWindowStartMs: 1_782_323_063_585,
      billingWindowEndMs: 1_784_915_063_585
    };

    const response = promptStartResponse({generationId: "generation", usageQuota}, promptConfig, promptConfig.version);

    expect(response.usageQuota).toEqual(usageQuota);
  });

  it("uses Firestore values as the canonical account snapshot", () => {
    const account = parseFirestoreAccountState(
      "user",
      "202606",
      {
        fields: {
          plan: {stringValue: "free"},
          freeGenerationsUsed: {integerValue: "0"},
          freeGenerationsLimit: {integerValue: "7"},
          aiMonthlyBudgetMicroUSD: {integerValue: "2500000"}
        }
      },
      {
        fields: {
          generatedCards: {integerValue: "20"},
          requestCount: {integerValue: "2"},
          costMicroUSD: {integerValue: "900"}
        }
      }
    );

    expect(account.freeGenerationsUsed).toBe(0);
    expect(account.freeGenerationsLimit).toBe(7);
    expect(account.monthlyBudgetMicroUSD).toBe(2_500_000);
    expect(account.monthlyUsage.costMicroUSD).toBe(900);
    expect(account.monthlyUsage.requestCount).toBe(2);
  });

  it("migrates only the retired default budget", () => {
    const migrated = parseFirestoreAccountState("user", "202609", {
      fields: {aiMonthlyBudgetMicroUSD: {integerValue: "2000000"}}
    }, null);
    const custom = parseFirestoreAccountState("custom", "202609", {
      fields: {aiMonthlyBudgetMicroUSD: {integerValue: "2500000"}}
    }, null);

    expect(migrated.monthlyBudgetMicroUSD).toBe(1_500_000);
    expect(custom.monthlyBudgetMicroUSD).toBe(2_500_000);
  });

  it("reads the server-owned rolling billing anchor", () => {
    const account = parseFirestoreAccountState("user", "202606", {
      fields: {
        premium: {booleanValue: true},
        aiBillingAnchorMs: {integerValue: "1782323063585"}
      }
    }, null);

    expect(account.aiBillingAnchorMs).toBe(1_782_323_063_585);
  });

  it("uses rolling 30-day billing windows from the activation anchor", () => {
    const anchor = Date.UTC(2026, 5, 24, 17, 44, 23, 585);
    const currentWindow = rollingBillingWindow(anchor, Date.UTC(2026, 6, 1, 8, 35, 0));
    const nextWindow = rollingBillingWindow(anchor, anchor + 31 * 24 * 60 * 60 * 1000);

    expect(currentWindow).toMatchObject({
      key: `r30_${anchor}`,
      startMs: anchor,
      endMs: anchor + 30 * 24 * 60 * 60 * 1000,
      basis: "rolling_30d"
    });
    expect(nextWindow.startMs).toBe(anchor + 30 * 24 * 60 * 60 * 1000);
  });

  it("allows only positive premium budget before a generation starts", () => {
    expect(premiumBudgetAllowsGeneration(1_500_000, 1_499_999, 0)).toBe(true);
    expect(premiumBudgetAllowsGeneration(1_500_000, 1_500_000, 0)).toBe(false);
    expect(premiumBudgetAllowsGeneration(1_500_000, 1_500_100, 0)).toBe(false);
  });

  it("uses the rolling period when finalizing a premium account", () => {
    const anchor = Date.UTC(2026, 5, 24, 17, 44, 23, 585);
    const now = Date.UTC(2026, 7, 8, 13, 56, 0);
    const account = parseFirestoreAccountState("user", "202608", {
      fields: {
        premium: {booleanValue: true},
        aiBillingAnchorMs: {integerValue: String(anchor)}
      }
    }, null);

    expect(usageWindowForAccount(account, now).key).toBe(rollingBillingWindow(anchor, now).key);
    expect(usageWindowForAccount(account, now).basis).toBe("rolling_30d");
  });

  it("lets the canonical premium boolean override the legacy plan string", () => {
    const account = parseFirestoreAccountState("user", "202606", {
      fields: {
        premium: {booleanValue: false},
        plan: {stringValue: "premium"}
      }
    }, null);

    expect(account.premium).toBe(false);
  });

  it("uses the current root usage projection instead of a stale monthly archive", () => {
    const account = parseFirestoreAccountState(
      "user",
      "202606",
      {
        fields: {
          premium: {booleanValue: true},
          aiUsage: {
            mapValue: {
              fields: {
                period: {stringValue: "202606"},
                requestCount: {integerValue: "9"},
                totalTokens: {integerValue: "123456"},
                costMicroUSD: {integerValue: "42000"}
              }
            }
          }
        }
      },
      {
        fields: {
          requestCount: {integerValue: "2"},
          totalTokens: {integerValue: "100"},
          costMicroUSD: {integerValue: "900"}
        }
      }
    );

    expect(account.monthlyUsage.requestCount).toBe(9);
    expect(account.monthlyUsage.totalTokens).toBe(123_456);
    expect(account.monthlyUsage.costMicroUSD).toBe(42_000);
  });

  it("falls back to the monthly archive when the root usage projection is empty", () => {
    const account = parseFirestoreAccountState(
      "user",
      "202606",
      {
        fields: {
          premium: {booleanValue: true},
          aiUsage: {
            mapValue: {
              fields: {
                period: {stringValue: "202606"},
                requestCount: {integerValue: "0"},
                totalTokens: {integerValue: "0"},
                costMicroUSD: {integerValue: "0"}
              }
            }
          }
        }
      },
      {
        fields: {
          requestCount: {integerValue: "7"},
          totalTokens: {integerValue: "800"},
          costMicroUSD: {integerValue: "5600"}
        }
      }
    );

    expect(account.monthlyUsage.requestCount).toBe(7);
    expect(account.monthlyUsage.totalTokens).toBe(800);
    expect(account.monthlyUsage.costMicroUSD).toBe(5_600);
  });

  it("increments canonical free and monthly usage from the latest Firestore value", () => {
    const account = parseFirestoreAccountState("user", "202606", {
      fields: {
        plan: {stringValue: "free"},
        freeGenerationsUsed: {integerValue: "0"},
        freeGenerationsLimit: {integerValue: "5"}
      }
    }, null);
    const next = applyingUsageDelta(account, {
      generationId: "generation",
      status: "succeeded",
      premiumAtStart: false,
      validatedCards: 15,
      costMicroUSD: 1200,
      promptTokens: 100,
      completionTokens: 50,
      totalTokens: 150,
      cacheHitTokens: 10,
      cacheMissTokens: 90
    });

    expect(next.freeGenerationsUsed).toBe(1);
    expect(next.monthlyUsage).toMatchObject({
      generatedCards: 15,
      requestCount: 1,
      freeRequestCount: 1,
      premiumRequestCount: 0,
      costMicroUSD: 1200,
      totalTokens: 150
    });
  });

  it("accounts failed premium provider cost without consuming free quota", () => {
    const account = parseFirestoreAccountState("user", "202606", {
      fields: {
        plan: {stringValue: "premium"},
        freeGenerationsUsed: {integerValue: "3"},
        freeGenerationsLimit: {integerValue: "5"}
      }
    }, null);
    const next = applyingUsageDelta(account, {
      generationId: "generation",
      status: "failed",
      premiumAtStart: true,
      validatedCards: 0,
      costMicroUSD: 400,
      promptTokens: 20,
      completionTokens: 0,
      totalTokens: 20,
      cacheHitTokens: 0,
      cacheMissTokens: 20
    });

    expect(next.freeGenerationsUsed).toBe(3);
    expect(next.monthlyUsage.requestCount).toBe(1);
    expect(next.monthlyUsage.premiumRequestCount).toBe(1);
    expect(next.monthlyUsage.costMicroUSD).toBe(400);
  });

  it("calculates exact DeepSeek cost from returned usage and response model", () => {
    const bytes = new TextEncoder().encode(JSON.stringify({
      id: "chatcmpl-test",
      model: "deepseek-flash",
      usage: {
        prompt_tokens: 1000,
        prompt_cache_hit_tokens: 100,
        prompt_cache_miss_tokens: 900,
        completion_tokens: 50,
        total_tokens: 1050
      },
      choices: [{finish_reason: "stop"}]
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "client-alias", true, pricingSelection("peak"));

    expect(metadata.accountingStatus).toBe("accounted");
    expect(metadata.pricingVersion).toBe("deepseek-flash@2026-09-10");
    expect(metadata.pricingBand).toBe("peak");
    expect(metadata.costMicroUSD).toBe(estimateCostMicroUSD(pricingConfig, "peak", 100, 900, 50));
    expect(metadata.responseID).toBe("chatcmpl-test");
  });

  it("does not double-count a fully cached prompt", () => {
    const bytes = new TextEncoder().encode(JSON.stringify({
      id: "chatcmpl-cached",
      model: "deepseek-flash",
      usage: {
        prompt_tokens: 1000,
        prompt_cache_hit_tokens: 1000,
        prompt_cache_miss_tokens: 0,
        completion_tokens: 50,
        total_tokens: 1050
      },
      choices: [{finish_reason: "stop"}]
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "deepseek-flash", true, pricingSelection("off_peak"));

    expect(metadata.cacheHitTokens).toBe(1000);
    expect(metadata.cacheMissTokens).toBe(0);
    expect(metadata.costMicroUSD).toBe(estimateCostMicroUSD(pricingConfig, "off_peak", 1000, 0, 50));
  });

  it("marks successful provider responses without usage as accounting errors", () => {
    const bytes = new TextEncoder().encode(JSON.stringify({
      id: "chatcmpl-test",
      model: "deepseek-flash",
      choices: [{finish_reason: "stop"}]
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "deepseek-flash", true, pricingSelection("peak"));

    expect(metadata.accountingStatus).toBe("accounting_error");
    expect(metadata.costMicroUSD).toBe(0);
    expect(metadata.usagePresent).toBe(false);
  });

  it("uses exact UTC peak boundaries and keeps weekends off-peak", () => {
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 14, 0, 59))).toBe("off_peak");
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 14, 1, 0))).toBe("peak");
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 14, 3, 59))).toBe("peak");
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 14, 4, 0))).toBe("off_peak");
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 14, 6, 0))).toBe("peak");
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 14, 10, 0))).toBe("off_peak");
    expect(pricingBandAt(pricingConfig, Date.UTC(2026, 8, 13, 2, 0))).toBe("off_peak");
  });

  it("rounds the combined token categories to the nearest microUSD", () => {
    expect(estimateCostMicroUSD(pricingConfig, "off_peak", 1, 1, 1)).toBe(1);
    expect(estimateCostMicroUSD(pricingConfig, "peak", 100, 900, 50)).toBe(331);
  });

  it("marks unknown response models as accounting errors", () => {
    const bytes = new TextEncoder().encode(JSON.stringify({
      model: "unknown-model",
      usage: {prompt_tokens: 1, completion_tokens: 1}
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "deepseek-flash", true, pricingSelection("peak"));

    expect(metadata.accountingStatus).toBe("accounting_error");
    expect(metadata.costMicroUSD).toBe(0);
  });

  it("rejects invalid pricing catalogs", () => {
    expect(() => validatedPricingConfig({
      ...pricingConfig,
      acceptedResponseModels: []
    })).toThrow();
  });

  it("atomically activates a new pricing version without rewriting history", async () => {
    const nextVersion = "deepseek-flash@test-activation";
    try {
      await env.AI_DB.prepare(
        `INSERT INTO ai_pricing_configs (
          version, model, accepted_response_models_json,
          peak_cache_hit_micro_usd_per_million, peak_cache_miss_micro_usd_per_million, peak_output_micro_usd_per_million,
          off_peak_cache_hit_micro_usd_per_million, off_peak_cache_miss_micro_usd_per_million, off_peak_output_micro_usd_per_million,
          peak_schedule_json, created_at_ms, activated_at_ms, review_after_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(
        nextVersion, "deepseek-flash", '["deepseek-flash"]',
        7_000, 310_000, 1_210_000, 4_000, 160_000, 610_000,
        JSON.stringify(pricingConfig.peakSchedule), Date.UTC(2026, 8, 19),
        Date.UTC(2026, 8, 19), Date.UTC(2026, 10, 19)
      ).run();
      await env.AI_DB.prepare(
        `INSERT INTO ai_pricing_active (singleton, version, updated_at_ms) VALUES (1, ?, ?)
         ON CONFLICT(singleton) DO UPDATE SET version = excluded.version, updated_at_ms = excluded.updated_at_ms`
      ).bind(nextVersion, Date.UTC(2026, 8, 19)).run();

      const selection = await activePricingSelection(env.AI_DB, Date.UTC(2026, 8, 20));
      const historical = await env.AI_DB.prepare(
        "SELECT version FROM ai_pricing_configs WHERE version = ?"
      ).bind(pricingConfig.version).first<{version: string}>();

      expect(selection.config.version).toBe(nextVersion);
      expect(historical?.version).toBe(pricingConfig.version);
    } finally {
      await env.AI_DB.prepare(
        "UPDATE ai_pricing_active SET version = ?, updated_at_ms = ? WHERE singleton = 1"
      ).bind(pricingConfig.version, Date.UTC(2026, 8, 19)).run();
      await env.AI_DB.prepare("DELETE FROM ai_pricing_configs WHERE version = ?").bind(nextVersion).run();
    }
  });
});

const pricingConfig: AIPricingConfig = validatedPricingConfig({
  version: "deepseek-flash@2026-09-10",
  model: "deepseek-flash",
  acceptedResponseModels: ["deepseek-flash"],
  peak: {
    cacheHitMicroUSDPerMillion: 6_000,
    cacheMissMicroUSDPerMillion: 300_000,
    outputMicroUSDPerMillion: 1_200_000
  },
  offPeak: {
    cacheHitMicroUSDPerMillion: 3_000,
    cacheMissMicroUSDPerMillion: 150_000,
    outputMicroUSDPerMillion: 600_000
  },
  peakSchedule: {
    weekdaysUTC: [1, 2, 3, 4, 5],
    intervalsUTC: [
      {startMinute: 60, endMinute: 240},
      {startMinute: 360, endMinute: 600}
    ]
  },
  activatedAtMs: Date.UTC(2026, 8, 10, 4),
  reviewAfterMs: Date.UTC(2026, 9, 10, 4)
});

function pricingSelection(band: "peak" | "off_peak"): PricingSelection {
  return {config: pricingConfig, band, selectedAtMs: Date.UTC(2026, 8, 14, 2)};
}
