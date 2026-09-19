CREATE TABLE IF NOT EXISTS account_deletions (
  uid TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('deleting', 'completed')),
  requested_at_ms INTEGER NOT NULL,
  completed_at_ms INTEGER
);

CREATE INDEX IF NOT EXISTS account_deletions_status
  ON account_deletions(status, requested_at_ms);
