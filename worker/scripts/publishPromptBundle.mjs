#!/usr/bin/env node

import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {spawnSync} from "node:child_process";

const requiredTemplateKeys = [
  "blueprint.batchContext",
  "blueprint.direct",
  "blueprint.map",
  "blueprint.reduce",
  "blueprint.repair",
  "blueprint.schema",
  "blueprint.system",
  "schema.flashcard",
  "schema.quiz",
  "sourceProfile.system",
  "sourceProfile.user",
  "system.userInstructions",
  "user.instructions",
  "system.base"
];

const args = process.argv.slice(2);
const bundlePath = args.find((arg) => !arg.startsWith("--"));
const activate = args.includes("--activate");
const useDefault = args.includes("--default");

if (!bundlePath && !useDefault) {
  console.error("Usage: node scripts/publishPromptBundle.mjs <bundle.json>|--default [--activate]");
  process.exit(1);
}

const bundle = useDefault
  ? (await import("../src/promptBundle.ts")).defaultPromptBundle
  : JSON.parse(await readFile(bundlePath, "utf8"));
validateBundle(bundle);
const hash = sha256(stableJSONString(bundle.templates));
const now = Date.now();
const status = activate ? "active" : "draft";
const sql = `
INSERT INTO ai_prompt_configs (version, hash, status, templates_json, created_at_ms, activated_at_ms)
VALUES (${sqlString(bundle.version)}, ${sqlString(hash)}, 'draft', ${sqlString(JSON.stringify(bundle.templates))}, ${now}, NULL)
ON CONFLICT(version) DO UPDATE SET
  hash = excluded.hash,
  status = 'draft',
  templates_json = excluded.templates_json;
${activate ? `
UPDATE ai_prompt_configs SET status = 'retired' WHERE status = 'active' AND version <> ${sqlString(bundle.version)};
UPDATE ai_prompt_configs SET status = 'active', activated_at_ms = ${now} WHERE version = ${sqlString(bundle.version)};
` : ""}
`;

const result = spawnSync("npx", ["wrangler", "d1", "execute", "quizflash-ai", "--remote", "--command", sql], {
  cwd: new URL("..", import.meta.url),
  stdio: "inherit"
});

if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Published prompt bundle ${bundle.version} (${hash}) as ${status}.`);

function validateBundle(bundle) {
  if (!bundle || typeof bundle !== "object") throw new Error("Bundle must be an object.");
  if (typeof bundle.version !== "string" || !bundle.version.trim()) throw new Error("Bundle version is required.");
  if (!bundle.templates || typeof bundle.templates !== "object" || Array.isArray(bundle.templates)) {
    throw new Error("Bundle templates must be an object.");
  }
  const missing = requiredTemplateKeys.filter((key) => typeof bundle.templates[key] !== "string" || !bundle.templates[key].trim());
  if (missing.length > 0) throw new Error(`Missing required templates: ${missing.join(", ")}`);
}

function stableJSONString(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJSONString).join(",")}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJSONString(value[key])}`).join(",")}}`;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}
