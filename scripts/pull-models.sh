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

Pull required LLM models inside the Ollama container.

Options:
  -c, --container NAME   Ollama container name (default: llm-interface-evaluation-ollama)
  -m, --models LIST      Comma-separated list of models to pull
  --minimal              Only pull the smallest model (qwen2.5:1.5b)
  --dry-run              Print the commands that would be executed without running them
  -h, --help             Show this help message and exit
  --version              Show version information and exit

Examples:
  $(basename "$0") --minimal
  $(basename "$0") -c my-ollama -m "qwen2.5:3b,llama3.2:3b"
EOF
}

# Defaults
container="llm-interface-evaluation-ollama"
models_str="qwen2.5:3b,qwen2.5:1.5b,phi3:mini,llama3.2:3b"
minimal=false
dry_run=false

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
    -m|--models)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      models_str="$2"
      shift 2
      ;;
    --minimal)
      minimal=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Set up models array
IFS=',' read -r -a models_array <<< "$models_str"

if [[ "$minimal" == "true" ]]; then
  log_info "Minimal mode enabled. Only pulling qwen2.5:1.5b..."
  models_array=("qwen2.5:1.5b")
fi

# Verify dependencies
for cmd in docker; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
done

# Verify container status
if [[ "$dry_run" == "false" ]]; then
  log_info "Checking Ollama container health for '${container}'..."
  if ! docker ps --filter "name=${container}" --filter "status=running" --format "{{.Names}}" | grep -q "^${container}$"; then
    log_error "Container '${container}' is not running."
    exit 1
  fi
fi

# Pulling models
log_info "Start pulling models..."
for model in "${models_array[@]}"; do
  log_info "--------------------------------------------------------"
  log_info "Model: ${model}"
  log_info "--------------------------------------------------------"
  if [[ "$dry_run" == "true" ]]; then
    log_info "[DRY-RUN] Would run: docker exec \"${container}\" ollama pull \"${model}\""
  else
    docker exec "${container}" ollama pull "${model}"
  fi
done

log_info "--------------------------------------------------------"
if [[ "$dry_run" == "true" ]]; then
  log_info "[DRY-RUN] Models pull dry-run finished successfully."
else
  log_info "All requested models have been pulled successfully!"
  log_info "Available models in Ollama:"
  docker exec "${container}" ollama list
fi
