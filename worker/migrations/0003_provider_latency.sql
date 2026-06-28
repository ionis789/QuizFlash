ALTER TABLE ai_provider_calls
  ADD COLUMN upstream_duration_ms REAL NOT NULL DEFAULT 0;
