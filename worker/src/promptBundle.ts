export type PromptBundle = {
  version: string;
  status: "draft" | "active" | "retired";
  templates: Record<string, string>;
};

export type PromptBundleRecord = PromptBundle & {
  hash: string;
};

export const requiredPromptTemplateKeys = [
  "schema.flashcard",
  "schema.quiz",
  "system.base",
  "title.system",
  "title.user"
] as const;

export const defaultPromptBundle: PromptBundle = {
  version: "v1",
  status: "active",
  templates: {
    "schema.flashcard": "canonical QuizFlash flashcard DTO schema template",
    "schema.quiz": "canonical QuizFlash quiz DTO schema template",
    "system.base": "QuizFlash AI card-generation system prompt v1. iOS owns dynamic composition and preserves the current runtime prompt order.",
    "title.system": "QuizFlash deck-title system prompt v1.",
    "title.user": "QuizFlash deck-title user prompt v1."
  }
};

export async function promptBundleHash(templates: Record<string, string>): Promise<string> {
  const bytes = new TextEncoder().encode(stableJSONString(templates));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function validatedPromptBundle(bundle: PromptBundle): Promise<PromptBundleRecord> {
  if (!bundle.version.trim()) throw new Error("Prompt bundle version is required.");
  const missing = requiredPromptTemplateKeys.filter((key) => !bundle.templates[key]?.trim());
  if (missing.length > 0) throw new Error(`Prompt bundle is missing required templates: ${missing.join(", ")}`);
  return {
    ...bundle,
    hash: await promptBundleHash(bundle.templates)
  };
}

function stableJSONString(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJSONString).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${stableJSONString(object[key])}`).join(",")}}`;
}
