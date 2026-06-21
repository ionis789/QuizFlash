#!/usr/bin/env node

/*
 * Analyze QuizFlash AI debug traces exported from
 * Library/Application Support/QuizFlash/ai_debug_traces.
 */

const fs = require("fs");
const path = require("path");

function usage() {
  console.error("Usage: node Scripts/analyze_ai_trace.js <trace-root-or-run-folder-or-export-json> [--run <run-id-or-folder-substring>]");
  process.exit(2);
}

function parseArgs(argv) {
  const args = argv.slice(2);
  if (args.length < 1) usage();

  const options = { root: args[0], run: null };
  for (let index = 1; index < args.length; index += 1) {
    if (args[index] === "--run" && args[index + 1]) {
      options.run = args[index + 1];
      index += 1;
    } else {
      usage();
    }
  }
  return options;
}

function isDirectory(filePath) {
  try {
    return fs.statSync(filePath).isDirectory();
  } catch {
    return false;
  }
}

function isFile(filePath) {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

function listRunFolders(root, requestedRun) {
  if (!isDirectory(root)) {
    throw new Error(`Trace path is not a directory: ${root}`);
  }

  const directEvents = path.join(root, "events.jsonl");
  if (fs.existsSync(directEvents)) {
    return [root];
  }

  const folders = fs.readdirSync(root)
    .map((entry) => path.join(root, entry))
    .filter(isDirectory)
    .filter((folder) => fs.existsSync(path.join(folder, "events.jsonl")))
    .sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);

  if (requestedRun) {
    const match = folders.find((folder) => path.basename(folder).includes(requestedRun));
    if (!match) {
      throw new Error(`No trace run matched: ${requestedRun}`);
    }
    return [match];
  }

  const generationFolders = folders.filter((folder) => path.basename(folder).includes("_generation_"));
  const candidates = generationFolders.length > 0 ? generationFolders : folders;

  if (candidates.length === 0) {
    throw new Error(`No trace runs found under: ${root}`);
  }
  return [candidates[0]];
}

function readJSONL(filePath) {
  return fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`Invalid JSONL at ${filePath}:${index + 1}: ${error.message}`);
      }
    });
}

function readEventsExport(filePath) {
  const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
  if (!Array.isArray(data.events)) {
    throw new Error(`Trace export does not contain an events array: ${filePath}`);
  }
  return data.events;
}

function numberFrom(metadata, key) {
  const value = metadata?.[key];
  if (value === undefined || value === null || value === "") return 0;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function stringFrom(metadata, key) {
  const value = metadata?.[key];
  return value === undefined || value === null ? "" : String(value);
}

function parsePayload(event) {
  if (!event.payload) return null;
  try {
    return JSON.parse(event.payload);
  } catch {
    return null;
  }
}

function extractCardsFromPayload(event) {
  const payload = parsePayload(event);
  if (!payload || typeof payload !== "object") return [];

  const content = payload.choices?.[0]?.message?.content;
  if (typeof content === "string") {
    try {
      const contentJSON = JSON.parse(content);
      if (Array.isArray(contentJSON.cards)) return contentJSON.cards;
      if (Array.isArray(contentJSON.flashcards)) return contentJSON.flashcards;
      if (Array.isArray(contentJSON.quiz_cards)) return contentJSON.quiz_cards;
    } catch {
      return [];
    }
  }

  if (Array.isArray(payload.flashcards)) return payload.flashcards;
  if (Array.isArray(payload.cards)) return payload.cards;
  if (Array.isArray(payload.quiz_cards)) return payload.quiz_cards;
  return [];
}

function extractCardsFromContentEvent(event) {
  if (!event.payload || event.stage !== "responseContentExtracted") return [];
  try {
    const payload = JSON.parse(event.payload);
    if (Array.isArray(payload.cards)) return payload.cards;
    if (Array.isArray(payload.flashcards)) return payload.flashcards;
    if (Array.isArray(payload.quiz_cards)) return payload.quiz_cards;
  } catch {
    return [];
  }
  return [];
}

function textLength(value) {
  if (typeof value === "string") return value.trim().length;
  if (Array.isArray(value)) {
    return value.map(textLength).reduce((sum, length) => sum + length, 0);
  }
  if (value && typeof value === "object") {
    return Object.values(value).map(textLength).reduce((sum, length) => sum + length, 0);
  }
  return 0;
}

function cardFront(card) {
  return zoneText(card?.front) || zoneText(card?.question) || card?.prompt || card?.front_zones || card?.question_zones || "";
}

function cardBack(card) {
  return zoneText(card?.back) || zoneText(card?.answer) || card?.answers || card?.back_zones || card?.answer_zones || "";
}

function zoneText(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map(zoneText).filter(Boolean).join("\n");
  if (Array.isArray(value.zones)) {
    return value.zones.map((zone) => zone.text ?? zone.value ?? "").filter(Boolean).join("\n");
  }
  if (typeof value.text === "string") return value.text;
  return "";
}

function analyzeCards(cardEvents) {
  const cards = cardEvents.flatMap((event) => {
    const contentCards = extractCardsFromContentEvent(event);
    return contentCards.length > 0 ? contentCards : extractCardsFromPayload(event);
  });
  const frontLengths = cards.map((card) => textLength(cardFront(card)));
  const backLengths = cards.map((card) => textLength(cardBack(card)));
  const signatures = cards.map((card) => JSON.stringify(card)).filter(Boolean);
  const fronts = cards.map((card) => JSON.stringify(cardFront(card))).filter(Boolean);
  const rawFormalLeaks = analyzeRawFormalLeaks(cards);

  return {
    count: cards.length,
    emptyFront: frontLengths.filter((length) => length === 0).length,
    emptyBack: backLengths.filter((length) => length === 0).length,
    duplicateExact: signatures.length - new Set(signatures).size,
    duplicateFront: fronts.length - new Set(fronts).size,
    frontAverage: average(frontLengths),
    backAverage: average(backLengths),
    frontMedian: median(frontLengths),
    backMedian: median(backLengths),
    frontMax: max(frontLengths),
    backMax: max(backLengths),
    rawFormalLeaks
  };
}

const rawFormalCharacterPattern = /[φψτΓΔΣΠΛΩΦΨ∀∃∈∉⊆⊂⊇⊃∅∧∨¬→↔⇒⇔⊢⊨⊥⊤□ᶜ₀₁₂₃₄₅₆₇₈₉⁰¹²³⁴⁵⁶⁷⁸⁹]/u;

function analyzeRawFormalLeaks(cards) {
  const leaks = [];
  for (const [index, card] of cards.entries()) {
    const front = cardFront(card);
    const back = cardBack(card);
    const frontLeak = containsRawFormalNotation(front);
    const backLeak = containsRawFormalNotation(back);
    if (frontLeak || backLeak) {
      leaks.push({
        index: index + 1,
        frontLeak,
        backLeak,
        front: preview(front),
        back: preview(back)
      });
    }
  }

  return {
    count: leaks.length,
    frontCount: leaks.filter((leak) => leak.frontLeak).length,
    backCount: leaks.filter((leak) => leak.backLeak).length,
    samples: leaks.slice(0, 12)
  };
}

function containsRawFormalNotation(value) {
  const text = stripMathAndCode(zoneText(value) || String(value ?? ""));
  return rawFormalCharacterPattern.test(text);
}

function stripMathAndCode(text) {
  return text
    .replace(/\$\$[\s\S]*?\$\$/g, "")
    .replace(/\$[^$]*\$/g, "")
    .replace(/`[^`]*`/g, "");
}

function preview(text) {
  return String(text ?? "").replace(/\s+/g, " ").trim().slice(0, 180);
}

function analyzePromptCapture(requestEvents) {
  const promptEvents = requestEvents.map((event) => {
    const payload = parsePayload(event);
    const messages = Array.isArray(payload?.messages) ? payload.messages : [];
    const system = messages.find((message) => message.role === "system");
    const user = [...messages].reverse().find((message) => message.role === "user");
    return {
      hasPayload: Boolean(event.payload),
      hasMessages: messages.length > 0,
      systemLength: textLength(system?.content),
      userLength: textLength(user?.content)
    };
  });

  return {
    requestCount: requestEvents.length,
    payloadCount: promptEvents.filter((event) => event.hasPayload).length,
    messagePayloadCount: promptEvents.filter((event) => event.hasMessages).length,
    systemPromptChars: promptEvents.reduce((sum, event) => sum + event.systemLength, 0),
    userPromptChars: promptEvents.reduce((sum, event) => sum + event.userLength, 0)
  };
}

function average(values) {
  if (values.length === 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function median(values) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function max(values) {
  return values.length === 0 ? 0 : Math.max(...values);
}

function batchKey(event) {
  const scope = event.scope ?? {};
  const metadata = event.metadata ?? {};
  const index = scope.batchIndex ?? scope.batch_index ?? metadata.batch_index ?? "?";
  const total = scope.totalBatches ?? scope.total_batches ?? metadata.total_batches ?? "?";
  return `${index}/${total}`;
}

function summarizeEvents(events, runLabel) {
  const responseEvents = events.filter((event) => event.stage === "responseReceived");
  const requestEvents = events.filter((event) => event.stage === "requestPrepared");
  const contentEvents = events.filter((event) => event.stage === "responseContentExtracted");
  const decodedEvents = events.filter((event) => event.stage === "decodePrepared");
  const completed = [...events].reverse().find((event) => event.stage === "runCompleted" || event.stage === "runFailed");
  const batches = responseEvents.map((event) => {
    const metadata = event.metadata ?? {};
    return {
      batch: batchKey(event),
      model: stringFrom(metadata, "response_model") || stringFrom(metadata, "model"),
      finishReason: stringFrom(metadata, "finish_reason"),
      promptTokens: numberFrom(metadata, "prompt_tokens"),
      completionTokens: numberFrom(metadata, "completion_tokens"),
      totalTokens: numberFrom(metadata, "total_tokens"),
      cacheHitTokens: numberFrom(metadata, "prompt_cache_hit_tokens"),
      cacheMissTokens: numberFrom(metadata, "prompt_cache_miss_tokens"),
      costMicroUSD: numberFrom(metadata, "estimated_cost_micro_usd"),
      rawBytes: numberFrom(metadata, "raw_response_bytes"),
      contentLength: numberFrom(metadata, "response_content_length"),
      source: event.scope?.sourceLabel ?? event.scope?.source_label ?? metadata.source_label ?? ""
    };
  });

  const totals = batches.reduce((accumulator, batch) => {
    accumulator.promptTokens += batch.promptTokens;
    accumulator.completionTokens += batch.completionTokens;
    accumulator.totalTokens += batch.totalTokens;
    accumulator.cacheHitTokens += batch.cacheHitTokens;
    accumulator.cacheMissTokens += batch.cacheMissTokens;
    accumulator.costMicroUSD += batch.costMicroUSD;
    accumulator.rawBytes += batch.rawBytes;
    return accumulator;
  }, {
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    cacheHitTokens: 0,
    cacheMissTokens: 0,
    costMicroUSD: 0,
    rawBytes: 0
  });

  const runMetadata = completed?.metadata ?? {};
  const cardStats = analyzeCards(contentEvents.length > 0 ? contentEvents : (decodedEvents.length > 0 ? decodedEvents : responseEvents));
  const promptCapture = analyzePromptCapture(requestEvents);
  const retryCount = events.filter((event) => event.stage === "retryScheduled").length;
  const decodeFailures = events.filter((event) => event.stage === "decodeFailed").length;
  const shortfall = events
    .filter((event) => event.stage === "batchCompleted")
    .map((event) => numberFrom(event.metadata, "shortfall_count"))
    .reduce((sum, value) => sum + value, 0);
  const acceptedCards = events
    .filter((event) => event.stage === "batchCompleted")
    .map((event) => numberFrom(event.metadata, "accepted_cards"))
    .reduce((sum, value) => sum + value, 0);
  const plannedCards = responseEvents
    .map((event) => numberFrom(event.metadata, "planned_card_count"))
    .reduce((sum, value) => sum + value, 0);

  return {
    runFolder: runLabel,
    eventCount: events.length,
    status: completed?.stage ?? "incomplete",
    targetCards: numberFrom(runMetadata, "target_cards") || plannedCards,
    generatedCards: numberFrom(runMetadata, "generated_cards") || acceptedCards,
    elapsedMs: numberFrom(runMetadata, "elapsed_ms") || numberFrom(runMetadata, "run_elapsed_ms"),
    requestCount: responseEvents.length,
    retryCount,
    decodeFailures,
    shortfall,
    totals,
    runUsage: {
      totalTokens: numberFrom(runMetadata, "ai_usage_total_tokens"),
      promptTokens: numberFrom(runMetadata, "ai_usage_prompt_tokens"),
      completionTokens: numberFrom(runMetadata, "ai_usage_completion_tokens"),
      cacheHitTokens: numberFrom(runMetadata, "ai_usage_prompt_cache_hit_tokens"),
      cacheMissTokens: numberFrom(runMetadata, "ai_usage_prompt_cache_miss_tokens"),
      costMicroUSD: numberFrom(runMetadata, "ai_usage_estimated_cost_micro_usd")
    },
    promptCapture,
    cardStats,
    batches
  };
}

function summarizeRun(runFolder) {
  return summarizeEvents(readJSONL(path.join(runFolder, "events.jsonl")), runFolder);
}

function printSummary(summary) {
  console.log(`Run: ${path.basename(summary.runFolder)}`);
  console.log(`Status: ${summary.status}`);
  console.log(`Cards: target=${summary.targetCards || "unknown"} generated=${summary.generatedCards || summary.cardStats.count}`);
  console.log(`Requests: ${summary.requestCount}, retries=${summary.retryCount}, decodeFailures=${summary.decodeFailures}, shortfall=${summary.shortfall}`);
  console.log(`Elapsed: ${summary.elapsedMs || "unknown"} ms`);
  console.log("");
  console.log("Usage totals from responses:");
  console.log(`  prompt=${summary.totals.promptTokens} completion=${summary.totals.completionTokens} total=${summary.totals.totalTokens}`);
  console.log(`  cacheHit=${summary.totals.cacheHitTokens} cacheMiss=${summary.totals.cacheMissTokens}`);
  console.log(`  costMicroUSD=${summary.totals.costMicroUSD} costUSD=${(summary.totals.costMicroUSD / 1_000_000).toFixed(6)}`);
  console.log(`  rawBytes=${summary.totals.rawBytes}`);
  console.log("");
  console.log("Usage totals from runCompleted:");
  console.log(`  prompt=${summary.runUsage.promptTokens} completion=${summary.runUsage.completionTokens} total=${summary.runUsage.totalTokens}`);
  console.log(`  cacheHit=${summary.runUsage.cacheHitTokens} cacheMiss=${summary.runUsage.cacheMissTokens}`);
  console.log(`  costMicroUSD=${summary.runUsage.costMicroUSD} costUSD=${(summary.runUsage.costMicroUSD / 1_000_000).toFixed(6)}`);
  console.log("");
  console.log("Card quality:");
  console.log(`  count=${summary.cardStats.count} duplicateExact=${summary.cardStats.duplicateExact} duplicateFront=${summary.cardStats.duplicateFront}`);
  console.log(`  emptyFront=${summary.cardStats.emptyFront} emptyBack=${summary.cardStats.emptyBack}`);
  console.log(`  frontAvg=${summary.cardStats.frontAverage.toFixed(1)} frontMedian=${summary.cardStats.frontMedian} frontMax=${summary.cardStats.frontMax}`);
  console.log(`  backAvg=${summary.cardStats.backAverage.toFixed(1)} backMedian=${summary.cardStats.backMedian} backMax=${summary.cardStats.backMax}`);
  console.log(`  rawFormalOutsideMath=${summary.cardStats.rawFormalLeaks.count} front=${summary.cardStats.rawFormalLeaks.frontCount} back=${summary.cardStats.rawFormalLeaks.backCount}`);
  for (const leak of summary.cardStats.rawFormalLeaks.samples) {
    console.log(`    #${leak.index} front=${leak.frontLeak ? "yes" : "no"} back=${leak.backLeak ? "yes" : "no"} F="${leak.front}" B="${leak.back}"`);
  }
  console.log("");
  console.log("Prompt capture:");
  console.log(`  requestPrepared=${summary.promptCapture.requestCount} payloads=${summary.promptCapture.payloadCount} messagePayloads=${summary.promptCapture.messagePayloadCount}`);
  console.log(`  systemPromptChars=${summary.promptCapture.systemPromptChars} userPromptChars=${summary.promptCapture.userPromptChars}`);
  console.log("");
  console.log("Batches:");
  for (const batch of summary.batches) {
    console.log([
      `  ${batch.batch}`,
      `model=${batch.model || "unknown"}`,
      `finish=${batch.finishReason || "unknown"}`,
      `tokens=${batch.totalTokens}`,
      `prompt=${batch.promptTokens}`,
      `completion=${batch.completionTokens}`,
      `cacheHit=${batch.cacheHitTokens}`,
      `cacheMiss=${batch.cacheMissTokens}`,
      `costMicroUSD=${batch.costMicroUSD}`,
      `rawBytes=${batch.rawBytes}`,
      `contentLen=${batch.contentLength}`,
      `source="${batch.source}"`
    ].join(" "));
  }
}

try {
  const options = parseArgs(process.argv);
  const inputPath = path.resolve(options.root);
  if (isFile(inputPath)) {
    printSummary(summarizeEvents(readEventsExport(inputPath), inputPath));
  } else {
    const [runFolder] = listRunFolders(inputPath, options.run);
    printSummary(summarizeRun(runFolder));
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
