import {SELF} from "cloudflare:test";
import {describe, expect, it} from "vitest";

describe("QuizFlash AI proxy", () => {
  it("returns a health response without touching provider credentials", async () => {
    const response = await SELF.fetch("https://example.test/health");

    expect(response.status).toBe(200);
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
});
