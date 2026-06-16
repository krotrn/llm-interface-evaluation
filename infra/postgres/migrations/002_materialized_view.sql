-- ============================================================
-- MATERIALIZED VIEWS
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS eval_run_summary AS
SELECT
  r.id AS run_id,
  r.started_at,
  r.git_commit,
  res.model,
  res.category,
  COUNT(*) AS total_cases,
  AVG(res.score) AS avg_score,
  SUM(CASE WHEN res.score = 1.0 THEN 1 ELSE 0 END) AS perfect_scores,
  AVG(res.latency_ms) AS avg_latency_ms
FROM eval_runs r
JOIN eval_results res ON res.run_id = r.id
WHERE r.status = 'completed'
GROUP BY r.id, r.started_at, r.git_commit, res.model, res.category;

CREATE UNIQUE INDEX IF NOT EXISTS idx_eval_run_summary_unique ON eval_run_summary(run_id, model, category);
