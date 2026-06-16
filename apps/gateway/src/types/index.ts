export interface InferenceRequest {
  prompt: string;
  model?: string;
  stream?: boolean;
  metadata?: Record<string, any>;
}

export interface InferenceResponse {
  request_id: string;
  status: "completed" | "queued" | "processing" | "failed";
  cache_hit: boolean;
  model_requested: string;
  model_used?: string;
  result?: string;
  latency_ms?: number;
  token_count?: number | null;
  cached_at?: string;
  similarity_score?: number;
  fallback_triggered?: boolean;
  job_id?: string;
  poll_url?: string;
  stream_url?: string;
  error?: {
    code: string;
    message: string;
    request_id?: string;
    models_attempted?: string[];
  };
}

export interface CacheEntry {
  prompt: string;
  result: string;
  model: string;
  cachedAt: string;
  embedding: number[];
}

export interface CacheHit {
  entry: CacheEntry;
  similarity: number;
}

export type CircuitBreakerState = "CLOSED" | "OPEN" | "HALF-OPEN";

export interface InferenceJob {
  requestId: string;
  prompt: string;
  model: string;
  stream: boolean;
  metadata: {
    clientIp: string;
    apiKey: string; // hashed for audit
    enqueuedAt: string;
    originalModel: string;
  };
}

export interface ScoringResult {
  score: number; // 0.0 to 1.0
  reason: string;
  raw_output: string;
  execution_output?: string;
  latency_ms: number;
}

export type ScorerType = "code-execution" | "exact-match" | "regex" | "llm-judge";

export interface TestCase {
  id: string;
  category: string;
  prompt: string;
  scorer_type: ScorerType;
  expected_output?: string;
  test_code?: string;
  reference_solution?: string;
}
