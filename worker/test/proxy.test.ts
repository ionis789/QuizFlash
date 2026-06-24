import {SELF} from "cloudflare:test";
import {describe, expect, it} from "vitest";
import {promptStartResponse} from "../src";
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
});
