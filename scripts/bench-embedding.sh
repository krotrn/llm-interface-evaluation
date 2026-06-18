#!/usr/bin/env bash

# Strict mode
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Script version
readonly SCRIPT_VERSION="1.0.0"

# Get absolute path to script and project root
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Logging helpers
log_info() {
  printf "\033[0;32m[INFO]\033[0m %s\n" "$*" >&2
}

log_warn() {
  printf "\033[0;33m[WARN]\033[0m %s\n" "$*" >&2
}

log_error() {
  printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2
}

# Print usage function
show_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run latency benchmark against the embedding service inside the docker container.

Options:
  -c, --container SERVICE  Docker compose service name (default: embedding)
  -t, --threshold MS       p99 latency threshold in milliseconds (default: 200.0)
  -r, --requests NUM       Number of requests to send (default: 100)
  -h, --help               Show this help message and exit
  --version                Show version information and exit

Examples:
  $(basename "$0") --threshold 150.0
  $(basename "$0") -c custom-embedding -r 50
EOF
}

# Defaults
container="embedding"
threshold="200.0"
requests="100"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0
      ;;
    --version)
      echo "$(basename "$0") v${SCRIPT_VERSION}"
      exit 0
      ;;
    -c|--container)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      container="$2"
      shift 2
      ;;
    -t|--threshold)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      threshold="$2"
      shift 2
      ;;
    -r|--requests)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      requests="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Validate inputs
if ! [[ "$threshold" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  log_error "Threshold must be a positive number: $threshold"
  exit 1
fi

if ! [[ "$requests" =~ ^[0-9]+$ ]] || (( requests <= 0 )); then
  log_error "Requests must be a positive integer: $requests"
  exit 1
fi

# Verify dependencies
for cmd in docker; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
done

# Verify container status
log_info "Checking if container/service '${container}' is running..."
cd -- "$PROJECT_ROOT" || exit 1

if ! docker compose ps --format json | grep -q "\"Service\":\"${container}\""; then
  # Fallback to checking by raw container name
  if ! docker ps --filter "name=${container}" --filter "status=running" --format "{{.Names}}" | grep -q "^${container}$"; then
    log_error "Container or Compose service '${container}' is not running."
    exit 1
  fi
fi

log_info "Running benchmark inside container '${container}'..."
log_info "Threshold: ${threshold}ms, Requests: ${requests}"

# Export environment variables for the python script inside compose exec
docker compose exec -T \
  -e LATENCY_THRESHOLD_MS="$threshold" \
  -e NUM_REQUESTS="$requests" \
  "$container" python3 - <<'EOF'
import json
import urllib.request
import time
import sys
import os

url = "http://localhost:8000/embed"
payload = json.dumps({"text": "What is Redis?"}).encode("utf-8")
headers = {"Content-Type": "application/json"}

# Read parameters from environment
threshold_ms = float(os.getenv("LATENCY_THRESHOLD_MS", "200.0"))
num_requests = int(os.getenv("NUM_REQUESTS", "100"))

latencies = []

print(f"Running latency benchmark: sending {num_requests} sequential requests to /embed...")

# Warmup request
try:
    req = urllib.request.Request(url, data=payload, headers=headers)
    with urllib.request.urlopen(req) as res:
        res.read()
except Exception as e:
    print(f"Error during warmup: {e}")
    sys.exit(1)

# Main loop
for i in range(num_requests):
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

if p99 >= threshold_ms:
    print(f"FAIL: p99 latency ({p99:.2f} ms) is greater than {threshold_ms} ms threshold")
    sys.exit(1)

print(f"PASS: p99 latency is under {threshold_ms} ms")
EOF
