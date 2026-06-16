CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- GATEWAY TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS cache_entries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prompt_hash     CHAR(64) NOT NULL,
  embedding       vector(384) NOT NULL,
  model           VARCHAR(100) NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at      TIMESTAMPTZ NOT NULL,
  hit_count       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_cache_entries_embedding ON cache_entries
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 10);
CREATE INDEX IF NOT EXISTS idx_cache_entries_expires ON cache_entries(expires_at);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inference_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL,
  prompt_hash     CHAR(64) NOT NULL,          -- SHA-256 of prompt
  model_requested VARCHAR(100) NOT NULL,
  model_used      VARCHAR(100) NOT NULL,      -- May differ if CB fired
  cache_hit       BOOLEAN NOT NULL DEFAULT FALSE,
  stream          BOOLEAN NOT NULL DEFAULT FALSE,
  latency_ms      INTEGER NOT NULL,
  token_count     INTEGER,
  error_message   TEXT,
  client_ip       INET,
  api_key_hash    CHAR(64),                   -- SHA-256 of API key
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inference_log_request_id ON inference_log(request_id);
CREATE INDEX IF NOT EXISTS idx_inference_log_created_at ON inference_log(created_at);
CREATE INDEX IF NOT EXISTS idx_inference_log_model_used ON inference_log(model_used);
CREATE INDEX IF NOT EXISTS idx_inference_log_cache_hit ON inference_log(cache_hit);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS circuit_breaker_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model           VARCHAR(100) NOT NULL,
  from_state      VARCHAR(20) NOT NULL,       -- CLOSED, OPEN, HALF-OPEN
  to_state        VARCHAR(20) NOT NULL,
  reason          VARCHAR(200),               -- 'error_rate_exceeded', 'queue_depth_exceeded', 'probe_success', 'probe_failure', 'cooldown_expired'
  error_rate      NUMERIC(5,4),               -- e.g. 0.5432
  queue_depth     INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cb_log_model ON circuit_breaker_log(model, created_at DESC);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dlq_entries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL,
  model           VARCHAR(100) NOT NULL,
  prompt_hash     CHAR(64) NOT NULL,
  error_message   TEXT,
  attempt_count   INTEGER NOT NULL DEFAULT 0,
  bullmq_job_id   VARCHAR(200),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ,
  resolution      VARCHAR(100)    -- 'manually_retried', 'discarded'
);

-- ============================================================
-- EVAL TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS eval_runs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  models          TEXT[] NOT NULL,            -- Array of model names
  categories      TEXT[] NOT NULL,            -- Array of category names
  total_cases     INTEGER NOT NULL,
  status          VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending, running, completed, failed
  started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ,
  triggered_by    VARCHAR(100),               -- 'cli', 'github-actions', 'cron'
  git_commit      CHAR(40),
  notes           TEXT
);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS eval_results (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id          UUID NOT NULL REFERENCES eval_runs(id) ON DELETE CASCADE,
  model           VARCHAR(100) NOT NULL,
  test_case_id    VARCHAR(50) NOT NULL,
  category        VARCHAR(50) NOT NULL,
  scorer_type     VARCHAR(30) NOT NULL,       -- code-execution, exact-match, regex, llm-judge
  score           NUMERIC(4,3) NOT NULL,      -- 0.000 to 1.000
  raw_output      TEXT,
  execution_output TEXT,                      -- For code-exec scorer
  latency_ms      INTEGER NOT NULL,
  error_message   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_eval_results_run_id ON eval_results(run_id);
CREATE INDEX IF NOT EXISTS idx_eval_results_model ON eval_results(model);
CREATE INDEX IF NOT EXISTS idx_eval_results_category ON eval_results(category);
CREATE UNIQUE INDEX IF NOT EXISTS idx_eval_results_unique ON eval_results(run_id, model, test_case_id);
