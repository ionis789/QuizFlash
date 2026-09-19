#!/usr/bin/env node

import {mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {spawnSync} from "node:child_process";

const args = process.argv.slice(2);
const configPath = args.find((argument) => !argument.startsWith("--"));
const activate = args.includes("--activate");

if (!configPath) {
  console.error("Usage: npm run pricing:publish -- <pricing.json> [--activate]");
  process.exit(1);
}

const config = JSON.parse(await readFile(configPath, "utf8"));
validateConfig(config);
const now = Date.now();
const status = activate ? "active" : "draft";
const statements = [
  `INSERT INTO ai_pricing_configs (
    version, model, accepted_response_models_json,
    peak_cache_hit_micro_usd_per_million, peak_cache_miss_micro_usd_per_million, peak_output_micro_usd_per_million,
    off_peak_cache_hit_micro_usd_per_million, off_peak_cache_miss_micro_usd_per_million, off_peak_output_micro_usd_per_million,
    peak_schedule_json, created_at_ms, activated_at_ms, review_after_ms
  ) VALUES (
    ${sqlString(config.version)}, ${sqlString(config.model)}, ${sqlString(JSON.stringify(config.acceptedResponseModels))},
    ${config.peak.cacheHitMicroUSDPerMillion}, ${config.peak.cacheMissMicroUSDPerMillion}, ${config.peak.outputMicroUSDPerMillion},
    ${config.offPeak.cacheHitMicroUSDPerMillion}, ${config.offPeak.cacheMissMicroUSDPerMillion}, ${config.offPeak.outputMicroUSDPerMillion},
    ${sqlString(JSON.stringify(config.peakSchedule))}, ${now}, ${config.activatedAtMs}, ${config.reviewAfterMs}
  )`
];

if (activate) {
  statements.push(
    `INSERT INTO ai_pricing_active (singleton, version, updated_at_ms)
     VALUES (1, ${sqlString(config.version)}, ${now})
     ON CONFLICT(singleton) DO UPDATE SET version = excluded.version, updated_at_ms = excluded.updated_at_ms`
  );
}

const temporaryDirectory = await mkdtemp(join(tmpdir(), "quizflash-pricing-"));
const sqlPath = join(temporaryDirectory, "publish-pricing.sql");
await writeFile(sqlPath, `${statements.join(";\n")};\n`);

const result = spawnSync(
  "npx",
  ["wrangler", "d1", "execute", "quizflash-ai", "--remote", "--file", sqlPath, "--yes"],
  {cwd: new URL("..", import.meta.url), stdio: "inherit"}
);
await rm(temporaryDirectory, {recursive: true, force: true});

if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Published pricing config ${config.version} as ${status}.`);

function validateConfig(config) {
  if (!config || typeof config !== "object") throw new Error("Pricing config must be an object.");
  requiredString(config.version, "version");
  const model = requiredString(config.model, "model").toLowerCase();
  if (!Array.isArray(config.acceptedResponseModels) || config.acceptedResponseModels.length === 0
    || config.acceptedResponseModels.some((value) => typeof value !== "string" || !value.trim())) {
    throw new Error("acceptedResponseModels must contain non-empty strings.");
  }
  if (!config.acceptedResponseModels.map((value) => value.trim().toLowerCase()).includes(model)) {
    throw new Error("The canonical model must be accepted.");
  }
  validateRates(config.peak, "peak");
  validateRates(config.offPeak, "offPeak");
  const schedule = config.peakSchedule;
  if (!schedule || !Array.isArray(schedule.weekdaysUTC) || schedule.weekdaysUTC.length === 0
    || schedule.weekdaysUTC.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
    throw new Error("peakSchedule.weekdaysUTC is invalid.");
  }
  if (!Array.isArray(schedule.intervalsUTC) || schedule.intervalsUTC.length === 0) {
    throw new Error("peakSchedule.intervalsUTC is required.");
  }
  const intervals = [...schedule.intervalsUTC].sort((left, right) => left.startMinute - right.startMinute);
  intervals.forEach((interval, index) => {
    if (!Number.isInteger(interval.startMinute) || !Number.isInteger(interval.endMinute)
      || interval.startMinute < 0 || interval.endMinute > 1440 || interval.startMinute >= interval.endMinute
      || (index > 0 && intervals[index - 1].endMinute > interval.startMinute)) {
      throw new Error("Peak intervals must be non-overlapping UTC minute ranges with exclusive ends.");
    }
  });
  if (!positiveInteger(config.activatedAtMs) || !positiveInteger(config.reviewAfterMs)
    || config.reviewAfterMs <= config.activatedAtMs) {
    throw new Error("activatedAtMs and reviewAfterMs are invalid.");
  }
}

function validateRates(rates, label) {
  if (!rates || !positiveInteger(rates.cacheHitMicroUSDPerMillion)
    || !positiveInteger(rates.cacheMissMicroUSDPerMillion)
    || !positiveInteger(rates.outputMicroUSDPerMillion)) {
    throw new Error(`${label} rates must be positive integer microUSD values per million tokens.`);
  }
}

function positiveInteger(value) {
  return Number.isSafeInteger(value) && value > 0;
}

function requiredString(value, label) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${label} is required.`);
  return value.trim();
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}
