CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- GATEWAY TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS cache_entries (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prompt_hash     TEXT NOT NULL,
  embedding       vector(384) NOT NULL,
  model           TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at      TIMESTAMPTZ NOT NULL,
  hit_count       INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT uq_cache_prompt_model UNIQUE (prompt_hash, model)
);

-- HNSW with inner product for fast normalized vector search
CREATE INDEX IF NOT EXISTS idx_cache_entries_embedding ON cache_entries
  USING hnsw (embedding vector_ip_ops);
CREATE INDEX IF NOT EXISTS idx_cache_entries_expires ON cache_entries(expires_at);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inference_log (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id      UUID NOT NULL,
  prompt_hash     TEXT NOT NULL,              -- SHA-256 of prompt
  model_requested TEXT NOT NULL,
  model_used      TEXT NOT NULL,              -- May differ if CB fired
  cache_hit       BOOLEAN NOT NULL DEFAULT FALSE,
  stream          BOOLEAN NOT NULL DEFAULT FALSE,
  latency_ms      INTEGER NOT NULL,
  token_count     INTEGER,
  error_message   TEXT,
  client_ip       INET,
  api_key_hash    TEXT,                       -- SHA-256 of API key
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inference_log_request_id ON inference_log(request_id);
CREATE INDEX IF NOT EXISTS idx_inference_log_created_at ON inference_log(created_at DESC);

-- Composite index for dashboard queries filtering by model over time
CREATE INDEX IF NOT EXISTS idx_inference_log_model_date 
  ON inference_log(model_used, created_at DESC);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS circuit_breaker_log (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  model           TEXT NOT NULL,
  from_state      TEXT NOT NULL,              -- CLOSED, OPEN, HALF-OPEN
  to_state        TEXT NOT NULL,
  reason          TEXT,                       -- 'error_rate_exceeded', 'queue_depth_exceeded', etc.
  error_rate      NUMERIC(5,4),
  queue_depth     INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cb_log_model ON circuit_breaker_log(model, created_at DESC);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dlq_entries (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id      UUID NOT NULL,
  model           TEXT NOT NULL,
  prompt_hash     TEXT NOT NULL,
  error_message   TEXT,
  attempt_count   INTEGER NOT NULL DEFAULT 0,
  bullmq_job_id   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at     TIMESTAMPTZ,
  resolution      TEXT                        -- 'manually_retried', 'discarded'
);

CREATE INDEX IF NOT EXISTS idx_dlq_entries_request_id ON dlq_entries(request_id);

-- Partial index for active (unresolved) failures
CREATE INDEX IF NOT EXISTS idx_dlq_entries_unresolved 
  ON dlq_entries(created_at) WHERE resolved_at IS NULL;

-- ============================================================
-- EVAL TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS eval_runs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- Keep UUID for run sharing
  models          TEXT[] NOT NULL,            -- Array of model names
  categories      TEXT[] NOT NULL,            -- Array of category names
  total_cases     INTEGER NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending', -- pending, running, completed, failed
  started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ,
  triggered_by    TEXT,                       -- 'cli', 'github-actions', 'cron'
  git_commit      TEXT,
  notes           TEXT
);

-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS eval_results (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id          UUID NOT NULL REFERENCES eval_runs(id) ON DELETE CASCADE,
  model           TEXT NOT NULL,
  test_case_id    TEXT NOT NULL,
  category        TEXT NOT NULL,
  scorer_type     TEXT NOT NULL,              -- code-execution, exact-match, regex, llm-judge
  score           NUMERIC(4,3) NOT NULL,      -- 0.000 to 1.000
  raw_output      TEXT,
  execution_output TEXT,                      -- For code-exec scorer
  latency_ms      INTEGER NOT NULL,
  error_message   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Note: Redundant idx_eval_results_run_id dropped as idx_eval_results_unique covers it
CREATE UNIQUE INDEX IF NOT EXISTS idx_eval_results_unique ON eval_results(run_id, model, test_case_id);
CREATE INDEX IF NOT EXISTS idx_eval_results_model ON eval_results(model);
CREATE INDEX IF NOT EXISTS idx_eval_results_category ON eval_results(category);
