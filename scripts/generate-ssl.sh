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

Generate a self-signed SSL certificate for Nginx.

Options:
  -d, --dir DIRECTORY    Output directory for SSL certificates (default: PROJECT_ROOT/infra/nginx/ssl)
  -y, --days DAYS        Certificate validity in days (default: 365)
  --dry-run              Print openSSL commands without executing them
  -h, --help             Show this help message and exit
  --version              Show version information and exit

Examples:
  $(basename "$0") --days 730
  $(basename "$0") -d /etc/nginx/ssl --dry-run
EOF
}

# Defaults
ssl_dir="${PROJECT_ROOT}/infra/nginx/ssl"
days="365"
dry_run=false
success=false

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
    -d|--dir)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      ssl_dir="$2"
      shift 2
      ;;
    -y|--days)
      if [[ -z "${2:-}" ]]; then
        log_error "Option $1 requires an argument."
        exit 1
      fi
      days="$2"
      shift 2
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

# Validate inputs
if ! [[ "$days" =~ ^[0-9]+$ ]] || (( days <= 0 )); then
  log_error "Days must be a positive integer: $days"
  exit 1
fi

# Verify dependencies
for cmd in openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
done

# Cleanup trap
cleanup() {
  if [[ "$dry_run" == "false" ]] && [[ "$success" == "false" ]]; then
    log_warn "SSL generation failed or interrupted. Cleaning up partial certificate files..."
    rm -f -- "${ssl_dir}/key.pem" "${ssl_dir}/cert.pem"
  fi
}
trap cleanup EXIT INT TERM

# Run generation
if [[ "$dry_run" == "true" ]]; then
  log_info "[DRY-RUN] Would create directory: ${ssl_dir}"
  log_info "[DRY-RUN] Would run: openssl req -x509 -nodes -days ${days} -newkey rsa:2048 \\"
  log_info "[DRY-RUN]   -keyout \"${ssl_dir}/key.pem\" \\"
  log_info "[DRY-RUN]   -out \"${ssl_dir}/cert.pem\" \\"
  log_info "[DRY-RUN]   -subj \"/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost\""
  log_info "[DRY-RUN] Would run: chmod 600 \"${ssl_dir}/key.pem\" && chmod 644 \"${ssl_dir}/cert.pem\""
  success=true
  exit 0
fi

log_info "Creating Nginx SSL directory at '${ssl_dir}'..."
mkdir -p "$ssl_dir"

log_info "Generating self-signed SSL certificate valid for ${days} days..."
openssl req -x509 -nodes -days "$days" -newkey rsa:2048 \
  -keyout "${ssl_dir}/key.pem" \
  -out "${ssl_dir}/cert.pem" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"

log_info "Setting secure permissions..."
chmod 600 "${ssl_dir}/key.pem"
chmod 644 "${ssl_dir}/cert.pem"

log_info "SSL Certificate generated successfully:"
log_info "  Cert: ${ssl_dir}/cert.pem"
log_info "  Key:  ${ssl_dir}/key.pem"

success=true
