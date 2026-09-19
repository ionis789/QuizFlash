export type PricingBand = "peak" | "off_peak";

export type PricingRates = {
  cacheHitMicroUSDPerMillion: number;
  cacheMissMicroUSDPerMillion: number;
  outputMicroUSDPerMillion: number;
};

export type PeakSchedule = {
  weekdaysUTC: number[];
  intervalsUTC: Array<{startMinute: number; endMinute: number}>;
};

export type AIPricingConfig = {
  version: string;
  model: string;
  acceptedResponseModels: string[];
  peak: PricingRates;
  offPeak: PricingRates;
  peakSchedule: PeakSchedule;
  activatedAtMs: number;
  reviewAfterMs: number;
};

export type PricingSelection = {
  config: AIPricingConfig;
  band: PricingBand;
  selectedAtMs: number;
};

type PricingConfigRow = {
  version: string;
  model: string;
  acceptedResponseModelsJSON: string;
  peakCacheHitMicroUSDPerMillion: number;
  peakCacheMissMicroUSDPerMillion: number;
  peakOutputMicroUSDPerMillion: number;
  offPeakCacheHitMicroUSDPerMillion: number;
  offPeakCacheMissMicroUSDPerMillion: number;
  offPeakOutputMicroUSDPerMillion: number;
  peakScheduleJSON: string;
  activatedAtMs: number;
  reviewAfterMs: number;
};

export async function activePricingSelection(
  database: D1Database,
  selectedAtMs: number
): Promise<PricingSelection> {
  const row = await database.prepare(
    `SELECT
      configs.version AS version,
      model,
      accepted_response_models_json AS "acceptedResponseModelsJSON",
      peak_cache_hit_micro_usd_per_million AS "peakCacheHitMicroUSDPerMillion",
      peak_cache_miss_micro_usd_per_million AS "peakCacheMissMicroUSDPerMillion",
      peak_output_micro_usd_per_million AS "peakOutputMicroUSDPerMillion",
      off_peak_cache_hit_micro_usd_per_million AS "offPeakCacheHitMicroUSDPerMillion",
      off_peak_cache_miss_micro_usd_per_million AS "offPeakCacheMissMicroUSDPerMillion",
      off_peak_output_micro_usd_per_million AS "offPeakOutputMicroUSDPerMillion",
      peak_schedule_json AS "peakScheduleJSON",
      activated_at_ms AS "activatedAtMs",
      review_after_ms AS "reviewAfterMs"
    FROM ai_pricing_active active
    JOIN ai_pricing_configs configs ON configs.version = active.version
    WHERE active.singleton = 1 AND configs.activated_at_ms <= ?
    LIMIT 1`
  ).bind(selectedAtMs).first<PricingConfigRow>();

  if (!row) {
    throw new Error("No active AI pricing configuration is available.");
  }

  const config = validatedPricingConfig({
    version: row.version,
    model: row.model,
    acceptedResponseModels: parseJSONArray(row.acceptedResponseModelsJSON, "accepted response models"),
    peak: {
      cacheHitMicroUSDPerMillion: row.peakCacheHitMicroUSDPerMillion,
      cacheMissMicroUSDPerMillion: row.peakCacheMissMicroUSDPerMillion,
      outputMicroUSDPerMillion: row.peakOutputMicroUSDPerMillion
    },
    offPeak: {
      cacheHitMicroUSDPerMillion: row.offPeakCacheHitMicroUSDPerMillion,
      cacheMissMicroUSDPerMillion: row.offPeakCacheMissMicroUSDPerMillion,
      outputMicroUSDPerMillion: row.offPeakOutputMicroUSDPerMillion
    },
    peakSchedule: parseJSONObject(row.peakScheduleJSON, "peak schedule") as PeakSchedule,
    activatedAtMs: row.activatedAtMs,
    reviewAfterMs: row.reviewAfterMs
  });

  return {
    config,
    band: pricingBandAt(config, selectedAtMs),
    selectedAtMs
  };
}

export function validatedPricingConfig(config: AIPricingConfig): AIPricingConfig {
  const version = nonEmpty(config.version, "Pricing version");
  const model = normalizedModel(nonEmpty(config.model, "Pricing model"));
  const acceptedResponseModels = [...new Set(config.acceptedResponseModels.map(normalizedModel))];
  if (acceptedResponseModels.length === 0 || acceptedResponseModels.some((value) => !value)) {
    throw new Error("At least one accepted response model is required.");
  }
  if (!acceptedResponseModels.includes(model)) {
    throw new Error("The canonical pricing model must be an accepted response model.");
  }

  const peak = validatedRates(config.peak, "peak");
  const offPeak = validatedRates(config.offPeak, "off-peak");
  const weekdaysUTC = [...new Set(config.peakSchedule.weekdaysUTC)];
  if (weekdaysUTC.length === 0 || weekdaysUTC.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
    throw new Error("Peak weekdays must contain UTC weekday integers from 0 through 6.");
  }
  const intervalsUTC = config.peakSchedule.intervalsUTC
    .map((interval) => ({startMinute: interval.startMinute, endMinute: interval.endMinute}))
    .sort((left, right) => left.startMinute - right.startMinute);
  if (intervalsUTC.length === 0) throw new Error("At least one peak interval is required.");
  for (let index = 0; index < intervalsUTC.length; index += 1) {
    const interval = intervalsUTC[index];
    if (!Number.isInteger(interval.startMinute) || !Number.isInteger(interval.endMinute)
      || interval.startMinute < 0 || interval.endMinute > 1_440
      || interval.startMinute >= interval.endMinute) {
      throw new Error("Peak intervals must be valid UTC minute ranges with exclusive end bounds.");
    }
    if (index > 0 && intervalsUTC[index - 1].endMinute > interval.startMinute) {
      throw new Error("Peak intervals must not overlap.");
    }
  }
  if (!positiveSafeInteger(config.activatedAtMs) || !positiveSafeInteger(config.reviewAfterMs)
    || config.reviewAfterMs <= config.activatedAtMs) {
    throw new Error("Pricing activation and review timestamps are invalid.");
  }

  return {
    version,
    model,
    acceptedResponseModels,
    peak,
    offPeak,
    peakSchedule: {weekdaysUTC, intervalsUTC},
    activatedAtMs: config.activatedAtMs,
    reviewAfterMs: config.reviewAfterMs
  };
}

export function pricingBandAt(config: AIPricingConfig, timestampMs: number): PricingBand {
  const date = new Date(timestampMs);
  const weekday = date.getUTCDay();
  if (!config.peakSchedule.weekdaysUTC.includes(weekday)) return "off_peak";
  const minute = date.getUTCHours() * 60 + date.getUTCMinutes();
  return config.peakSchedule.intervalsUTC.some(
    (interval) => minute >= interval.startMinute && minute < interval.endMinute
  ) ? "peak" : "off_peak";
}

export function pricedModelIsAccepted(config: AIPricingConfig, responseModel: string): boolean {
  return config.acceptedResponseModels.includes(normalizedModel(responseModel));
}

export function estimateCostMicroUSD(
  config: AIPricingConfig,
  band: PricingBand,
  cacheHitTokens: number,
  cacheMissTokens: number,
  completionTokens: number
): number {
  const rates = band === "peak" ? config.peak : config.offPeak;
  const numerator =
    nonNegativeInteger(cacheHitTokens) * rates.cacheHitMicroUSDPerMillion
    + nonNegativeInteger(cacheMissTokens) * rates.cacheMissMicroUSDPerMillion
    + nonNegativeInteger(completionTokens) * rates.outputMicroUSDPerMillion;
  if (!Number.isSafeInteger(numerator)) throw new Error("AI pricing calculation exceeded the safe integer range.");
  return Math.round(numerator / 1_000_000);
}

function validatedRates(rates: PricingRates, label: string): PricingRates {
  const values = [
    rates.cacheHitMicroUSDPerMillion,
    rates.cacheMissMicroUSDPerMillion,
    rates.outputMicroUSDPerMillion
  ];
  if (values.some((value) => !positiveSafeInteger(value))) {
    throw new Error(`${label} rates must be positive integer microUSD values per million tokens.`);
  }
  return {...rates};
}

function positiveSafeInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}

function nonNegativeInteger(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0;
}

function normalizedModel(value: string): string {
  return value.trim().toLowerCase();
}

function nonEmpty(value: string, label: string): string {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${label} is required.`);
  return trimmed;
}

function parseJSONArray(value: string, label: string): string[] {
  const parsed = JSON.parse(value) as unknown;
  if (!Array.isArray(parsed) || parsed.some((item) => typeof item !== "string")) {
    throw new Error(`The ${label} JSON is invalid.`);
  }
  return parsed;
}

function parseJSONObject(value: string, label: string): Record<string, unknown> {
  const parsed = JSON.parse(value) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`The ${label} JSON is invalid.`);
  }
  return parsed as Record<string, unknown>;
}
