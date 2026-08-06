import {SELF} from "cloudflare:test";
import {describe, expect, it} from "vitest";
import {estimateCostMicroUSD, extractProviderMetadata, promptStartResponse, providerOperation, rollingBillingWindow, validatedCardCount, validatedCardCountForTarget} from "../src";
import {applyingUsageDelta, parseFirestoreAccountState} from "../src/firestoreUsage";
import {defaultPromptBundle, validatedPromptBundle} from "../src/promptBundle";

describe("QuizFlash AI proxy", () => {
  it("publishes the exact blueprint schema placeholder on final-output templates", () => {
    expect(defaultPromptBundle.version).toBe("v6");
    expect(defaultPromptBundle.templates["blueprint.schema"]).not.toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.direct"]).toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.reduce"]).toContain("{{schemaVersion}}");
    expect(defaultPromptBundle.templates["blueprint.repair"]).toContain("{{schemaVersion}}");
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
    await expect(response.json()).resolves.toEqual({ok: true});
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
      model: "deepseek-v4-flash",
      usage: {
        prompt_tokens: 1000,
        prompt_cache_hit_tokens: 100,
        prompt_cache_miss_tokens: 900,
        completion_tokens: 50,
        total_tokens: 1050
      },
      choices: [{finish_reason: "stop"}]
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "client-alias", true);

    expect(metadata.accountingStatus).toBe("accounted");
    expect(metadata.pricingVersion).toBe("deepseek-v4-flash@2026-06");
    expect(metadata.costMicroUSD).toBe(estimateCostMicroUSD("deepseek-v4-flash", 100, 900, 50));
    expect(metadata.responseID).toBe("chatcmpl-test");
  });

  it("does not double-count a fully cached prompt", () => {
    const bytes = new TextEncoder().encode(JSON.stringify({
      id: "chatcmpl-cached",
      model: "deepseek-v4-flash",
      usage: {
        prompt_tokens: 1000,
        prompt_cache_hit_tokens: 1000,
        prompt_cache_miss_tokens: 0,
        completion_tokens: 50,
        total_tokens: 1050
      },
      choices: [{finish_reason: "stop"}]
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "deepseek-v4-flash", true);

    expect(metadata.cacheHitTokens).toBe(1000);
    expect(metadata.cacheMissTokens).toBe(0);
    expect(metadata.costMicroUSD).toBe(estimateCostMicroUSD("deepseek-v4-flash", 1000, 0, 50));
  });

  it("marks successful provider responses without usage as accounting errors", () => {
    const bytes = new TextEncoder().encode(JSON.stringify({
      id: "chatcmpl-test",
      model: "deepseek-v4-flash",
      choices: [{finish_reason: "stop"}]
    })).buffer;

    const metadata = extractProviderMetadata(bytes, "deepseek-v4-flash", true);

    expect(metadata.accountingStatus).toBe("accounting_error");
    expect(metadata.costMicroUSD).toBe(0);
    expect(metadata.usagePresent).toBe(false);
  });
});
