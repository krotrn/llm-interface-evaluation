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

Test Ollama models via API inside the gateway embedding container.

Options:
  -c, --container SERVICE  Docker compose service name (default: embedding)
  --host HOST              Ollama host address (default: ollama:11434)
  -m, --models LIST        Comma-separated list of models to test
  -h, --help               Show this help message and exit
  --version                Show version information and exit

Examples:
  $(basename "$0") --host localhost:11434
  $(basename "$0") -m "qwen2.5:1.5b,phi3:mini"
EOF
}

# Defaults
container="embedding"
ollama_host="ollama:11434"
models_str="qwen2.5:3b,qwen2.5:1.5b,phi3:mini,llama3.2:3b"

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
    --host)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      ollama_host="$2"
      shift 2
      ;;
    -m|--models)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      models_str="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

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

log_info "Running Ollama API tests inside container '${container}'..."
log_info "Ollama host: ${ollama_host}, models: ${models_str}"

# Export environment variables for the python script inside compose exec
docker compose exec -T \
  -e OLLAMA_HOST="$ollama_host" \
  -e OLLAMA_MODELS="$models_str" \
  "$container" python3 - <<'EOF'
import json
import urllib.request
import sys
import os

ollama_host = os.getenv("OLLAMA_HOST", "ollama:11434")
url = f"http://{ollama_host}/api/generate"

models_str = os.getenv("OLLAMA_MODELS", "qwen2.5:3b,qwen2.5:1.5b,phi3:mini,llama3.2:3b")
models = [m.strip() for m in models_str.split(",") if m.strip()]

pass_count = 0

print("Testing Ollama models via API inside container...")

for model in models:
    print(f"Testing model '{model}'... ", end="", flush=True)
    
    payload = json.dumps({
        "model": model,
        "prompt": "Say hello in one word.",
        "stream": False
    }).encode("utf-8")
    
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            response_data = json.loads(res.read().decode("utf-8"))
            text = response_data.get("response", "").strip()
            done = response_data.get("done", False)
            
            if done and text:
                print(f"\033[0;32mPASS\033[0m (Response: '{text}')")
                pass_count += 1
            else:
                print(f"\033[0;31mFAIL\033[0m (Response invalid: {response_data})")
    except Exception as e:
        print(f"\033[0;31mFAIL\033[0m (Error: {e})")

print("--------------------------------------------------------")
if pass_count == len(models):
    print(f"\033[0;32m{pass_count}/{len(models)} PASS\033[0m")
    sys.exit(0)
else:
    print(f"\033[0;31m{pass_count}/{len(models)} PASS\033[0m")
    sys.exit(1)
EOF
