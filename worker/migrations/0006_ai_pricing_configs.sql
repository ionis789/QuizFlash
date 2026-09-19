CREATE TABLE IF NOT EXISTS ai_pricing_configs (
  version TEXT PRIMARY KEY,
  model TEXT NOT NULL,
  accepted_response_models_json TEXT NOT NULL,
  peak_cache_hit_micro_usd_per_million INTEGER NOT NULL CHECK(peak_cache_hit_micro_usd_per_million > 0),
  peak_cache_miss_micro_usd_per_million INTEGER NOT NULL CHECK(peak_cache_miss_micro_usd_per_million > 0),
  peak_output_micro_usd_per_million INTEGER NOT NULL CHECK(peak_output_micro_usd_per_million > 0),
  off_peak_cache_hit_micro_usd_per_million INTEGER NOT NULL CHECK(off_peak_cache_hit_micro_usd_per_million > 0),
  off_peak_cache_miss_micro_usd_per_million INTEGER NOT NULL CHECK(off_peak_cache_miss_micro_usd_per_million > 0),
  off_peak_output_micro_usd_per_million INTEGER NOT NULL CHECK(off_peak_output_micro_usd_per_million > 0),
  peak_schedule_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  activated_at_ms INTEGER NOT NULL,
  review_after_ms INTEGER NOT NULL CHECK(review_after_ms > activated_at_ms)
);

CREATE TABLE IF NOT EXISTS ai_pricing_active (
  singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
  version TEXT NOT NULL REFERENCES ai_pricing_configs(version),
  updated_at_ms INTEGER NOT NULL
);

ALTER TABLE ai_provider_calls
  ADD COLUMN pricing_band TEXT CHECK(pricing_band IN ('peak', 'off_peak'));

CREATE INDEX IF NOT EXISTS ai_provider_calls_accounting_status
  ON ai_provider_calls(accounting_status, generation_id);

INSERT INTO ai_pricing_configs (
  version,
  model,
  accepted_response_models_json,
  peak_cache_hit_micro_usd_per_million,
  peak_cache_miss_micro_usd_per_million,
  peak_output_micro_usd_per_million,
  off_peak_cache_hit_micro_usd_per_million,
  off_peak_cache_miss_micro_usd_per_million,
  off_peak_output_micro_usd_per_million,
  peak_schedule_json,
  created_at_ms,
  activated_at_ms,
  review_after_ms
) VALUES (
  'deepseek-flash@2026-09-10',
  'deepseek-flash',
  '["deepseek-flash"]',
  6000,
  300000,
  1200000,
  3000,
  150000,
  600000,
  '{"weekdaysUTC":[1,2,3,4,5],"intervalsUTC":[{"startMinute":60,"endMinute":240},{"startMinute":360,"endMinute":600}]}',
  1789012800000,
  1789012800000,
  1791604800000
);

INSERT INTO ai_pricing_active (singleton, version, updated_at_ms)
VALUES (1, 'deepseek-flash@2026-09-10', 1789012800000);
