CREATE TABLE IF NOT EXISTS ai_prompt_configs (
  version TEXT PRIMARY KEY,
  hash TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('draft', 'active', 'retired')),
  templates_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  activated_at_ms INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS ai_prompt_configs_single_active
  ON ai_prompt_configs(status)
  WHERE status = 'active';

ALTER TABLE ai_generations ADD COLUMN prompt_version TEXT;
