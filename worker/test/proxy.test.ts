import {SELF} from "cloudflare:test";
import {describe, expect, it} from "vitest";
import {estimateCostMicroUSD, extractProviderMetadata, promptStartResponse} from "../src";
import {defaultPromptBundle, validatedPromptBundle} from "../src/promptBundle";

describe("QuizFlash AI proxy", () => {
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
      percent: 0.6
    };

    const response = promptStartResponse({generationId: "generation", usageQuota}, promptConfig, promptConfig.version);

    expect(response.usageQuota).toEqual(usageQuota);
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
