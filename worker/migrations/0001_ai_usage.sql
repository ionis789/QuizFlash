CREATE TABLE IF NOT EXISTS ai_generations (
  id TEXT PRIMARY KEY,
  uid TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  status TEXT NOT NULL,
  premium INTEGER NOT NULL,
  target_cards INTEGER NOT NULL,
  validated_cards INTEGER NOT NULL DEFAULT 0,
  prompt_hash TEXT,
  total_prompt_tokens INTEGER NOT NULL DEFAULT 0,
  total_completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  total_cache_hit_tokens INTEGER NOT NULL DEFAULT 0,
  total_cache_miss_tokens INTEGER NOT NULL DEFAULT 0,
  cost_micro_usd INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  completed_at_ms INTEGER,
  UNIQUE(uid, idempotency_key)
);

CREATE INDEX IF NOT EXISTS ai_generations_uid_created_at
  ON ai_generations(uid, created_at_ms DESC);

CREATE TABLE IF NOT EXISTS ai_provider_calls (
  provider_call_id TEXT PRIMARY KEY,
  generation_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  requested_model TEXT NOT NULL,
  response_model TEXT,
  provider_response_id TEXT,
  http_status INTEGER NOT NULL,
  finish_reason TEXT,
  raw_response_bytes INTEGER NOT NULL DEFAULT 0,
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  cache_hit_tokens INTEGER NOT NULL DEFAULT 0,
  cache_miss_tokens INTEGER NOT NULL DEFAULT 0,
  estimated_cost_micro_usd INTEGER NOT NULL DEFAULT 0,
  response_ciphertext TEXT,
  response_iv TEXT,
  response_expires_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS ai_provider_calls_expiry
  ON ai_provider_calls(response_expires_at_ms);

CREATE TABLE IF NOT EXISTS ai_monthly_usage (
  uid TEXT NOT NULL,
  period TEXT NOT NULL,
  generated_cards INTEGER NOT NULL DEFAULT 0,
  request_count INTEGER NOT NULL DEFAULT 0,
  cost_micro_usd INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(uid, period)
);

CREATE TABLE IF NOT EXISTS ai_free_quota (
  uid TEXT PRIMARY KEY,
  used_generations INTEGER NOT NULL DEFAULT 0,
  limit_generations INTEGER NOT NULL DEFAULT 5,
  initialized_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
