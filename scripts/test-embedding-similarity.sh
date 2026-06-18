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

Test embedding similarity between sample queries inside the embedding container.

Options:
  -c, --container SERVICE  Docker compose service name (default: embedding)
  --high THRESHOLD         Expected minimum similarity for related prompts (default: 0.85)
  --low THRESHOLD          Expected maximum similarity for unrelated prompts (default: 0.5)
  -h, --help               Show this help message and exit
  --version                Show version information and exit

Examples:
  $(basename "$0") --high 0.90
  $(basename "$0") -c custom-embedding
EOF
}

# Defaults
container="embedding"
high_threshold="0.85"
low_threshold="0.5"

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
    --high)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      high_threshold="$2"
      shift 2
      ;;
    --low)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      low_threshold="$2"
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
if ! [[ "$high_threshold" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  log_error "High threshold must be a valid float: $high_threshold"
  exit 1
fi

if ! [[ "$low_threshold" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  log_error "Low threshold must be a valid float: $low_threshold"
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

log_info "Running similarity test inside container '${container}'..."
log_info "High threshold: ${high_threshold}, Low threshold: ${low_threshold}"

# Export environment variables for the python script inside compose exec
docker compose exec -T \
  -e SIM_HIGH_THRESHOLD="$high_threshold" \
  -e SIM_LOW_THRESHOLD="$low_threshold" \
  "$container" python3 - <<'EOF'
import json
import urllib.request
import sys
import os

url = "http://localhost:8000/embed"

sim_high = float(os.getenv("SIM_HIGH_THRESHOLD", "0.85"))
sim_low = float(os.getenv("SIM_LOW_THRESHOLD", "0.5"))

def get_embedding(text):
    req = urllib.request.Request(
        url,
        data=json.dumps({"text": text}).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as res:
        if res.status != 200:
            raise RuntimeError(f"Unexpected status {res.status}")
        data = json.loads(res.read().decode("utf-8"))
        if "embedding" not in data:
            raise ValueError(f"Missing embedding field: {data}")
        return data["embedding"]

def dot_product(v1, v2):
    return sum(a * b for a, b in zip(v1, v2))

try:
    e1 = get_embedding("What is Redis?")
    e2 = get_embedding("Explain Redis to me")
    e3 = get_embedding("How do I make pasta?")
except Exception as e:
    print(f"Error fetching embeddings: {e}")
    sys.exit(1)

sim_1_2 = dot_product(e1, e2)
sim_1_3 = dot_product(e1, e3)

print(f'Similarity between "What is Redis?" and "Explain Redis to me": {sim_1_2:.4f}')
print(f'Similarity between "What is Redis?" and "How do I make pasta?": {sim_1_3:.4f}')

success = True
if sim_1_2 <= sim_high:
    print(f"FAIL: similarity between Q1 and Q2 should be > {sim_high}")
    success = False
else:
    print(f"PASS: similarity between Q1 and Q2 > {sim_high}")

if sim_1_3 >= sim_low:
    print(f"FAIL: similarity between Q1 and Q3 should be < {sim_low}")
    success = False
else:
    print(f"PASS: similarity between Q1 and Q3 < {sim_low}")

if not success:
    sys.exit(1)
print("All checks passed successfully!")
EOF