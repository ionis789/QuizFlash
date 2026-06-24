#!/usr/bin/env node

import {mkdtemp, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {spawnSync} from "node:child_process";

const [plan, rawLimit] = process.argv.slice(2);

if (!plan || !rawLimit) {
  console.error("Usage: node scripts/setPlanLimit.mjs <plan> <limitMicroUSD>");
  process.exit(1);
}

if (!/^[a-z][a-z0-9_-]{0,31}$/.test(plan)) {
  console.error("Plan must be a lowercase identifier.");
  process.exit(1);
}

const limitMicroUSD = Number(rawLimit);
if (!Number.isInteger(limitMicroUSD) || limitMicroUSD < 0) {
  console.error("limitMicroUSD must be a non-negative integer.");
  process.exit(1);
}

const now = Date.now();
const period = "monthly";
const sql = `
UPDATE ai_plan_limits
SET active = 0, updated_at_ms = ${now}
WHERE plan = ${sqlString(plan)} AND period = ${sqlString(period)} AND active = 1;
INSERT INTO ai_plan_limits (plan, limit_micro_usd, period, active, updated_at_ms)
VALUES (${sqlString(plan)}, ${limitMicroUSD}, ${sqlString(period)}, 1, ${now});
`;

const tempDir = await mkdtemp(join(tmpdir(), "quizflash-plan-limit-"));
const sqlPath = join(tempDir, "set-plan-limit.sql");
await writeFile(sqlPath, sql);

const result = spawnSync("npx", ["wrangler", "d1", "execute", "quizflash-ai", "--remote", "--file", sqlPath], {
  cwd: new URL("..", import.meta.url),
  stdio: "inherit"
});
await rm(tempDir, {recursive: true, force: true});

if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Set ${plan} ${period} AI limit to ${limitMicroUSD} microUSD.`);

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}
