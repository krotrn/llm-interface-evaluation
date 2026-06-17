from prometheus_client import Counter, Histogram

# Counter to track total embedding requests
llmforge_embedding_requests_total = Counter(
    "llmforge_embedding_requests_total",
    "Total number of embedding requests",
    ["endpoint", "status"],
)

# Histogram to track latency of embedding requests
llmforge_embedding_duration_seconds = Histogram(
    "llmforge_embedding_duration_seconds",
    "Duration of embedding requests in seconds",
    ["endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0]
)
