CREATE TABLE IF NOT EXISTS billing_webhook_events (
  event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  event_timestamp_ms INTEGER NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('processing', 'processed', 'failed')),
  payload_json TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 1,
  received_at_ms INTEGER NOT NULL,
  processed_at_ms INTEGER,
  last_error TEXT
);

CREATE INDEX IF NOT EXISTS billing_webhook_events_retry
  ON billing_webhook_events(status, received_at_ms);
