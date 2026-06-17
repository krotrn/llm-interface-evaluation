#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Run the python benchmark script inside the running embedding container
docker compose exec -T embedding python3 - <<'EOF'
import json
import urllib.request
import time
import sys

url = "http://localhost:8000/embed"
payload = json.dumps({"text": "What is Redis?"}).encode("utf-8")
headers = {"Content-Type": "application/json"}

latencies = []

print("Running latency benchmark: sending 100 sequential requests to /embed...")

# Warmup request
try:
    req = urllib.request.Request(url, data=payload, headers=headers)
    with urllib.request.urlopen(req) as res:
        res.read()
except Exception as e:
    print(f"Error during warmup: {e}")
    sys.exit(1)

# Main loop
for i in range(100):
    start = time.perf_counter()
    try:
        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req) as res:
            res.read()
        duration_ms = (time.perf_counter() - start) * 1000.0
        latencies.append(duration_ms)
    except Exception as e:
        print(f"Error at request {i}: {e}")
        sys.exit(1)

# Calculate percentiles
latencies.sort()
p50 = latencies[len(latencies) // 2]
p99 = latencies[int(len(latencies) * 0.99) - 1]

print(f"Benchmark completed successfully:")
print(f"  Total requests: {len(latencies)}")
print(f"  p50 Latency:    {p50:.2f} ms")
print(f"  p99 Latency:    {p99:.2f} ms")

if p99 >= 200.0:
    print(f"FAIL: p99 latency ({p99:.2f} ms) is greater than 200 ms threshold")
    sys.exit(1)

print("PASS: p99 latency is under 200 ms")
EOF
