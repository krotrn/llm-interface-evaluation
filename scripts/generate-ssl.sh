#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Directory where script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SSL_DIR="$PROJECT_ROOT/infra/nginx/ssl"

echo "Creating Nginx SSL directory at $SSL_DIR..."
mkdir -p "$SSL_DIR"

echo "Generating self-signed SSL certificate..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/key.pem" \
  -out "$SSL_DIR/cert.pem" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"

echo "SSL Certificate generated successfully:"
echo "  Cert: $SSL_DIR/cert.pem"
echo "  Key:  $SSL_DIR/key.pem"
chmod 600 "$SSL_DIR/key.pem"
chmod 644 "$SSL_DIR/cert.pem"
