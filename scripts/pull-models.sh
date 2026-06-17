#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

CONTAINER_NAME="llm-interface-evaluation-ollama"

# Models to pull
MODELS=(
  "qwen2.5:3b"
  "qwen2.5:1.5b"
  "phi3:mini"
  "llama3.2:3b"
)

# Minimal mode: only pull the smallest model
MINIMAL=false

for arg in "$@"; do
  case $arg in
    --minimal)
      MINIMAL=true
      shift
      ;;
  esac
done

if [ "$MINIMAL" = true ]; then
  echo "Minimal mode enabled. Only pulling qwen2.5:1.5b..."
  MODELS=("qwen2.5:1.5b")
fi

echo "Checking Ollama container health..."
if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
  echo "Error: $CONTAINER_NAME container is not running."
  exit 1
fi

echo "Start pulling models..."
for model in "${MODELS[@]}"; do
  echo "--------------------------------------------------------"
  echo "Pulling model: $model"
  echo "--------------------------------------------------------"
  # Run ollama pull inside the container
  docker exec "$CONTAINER_NAME" ollama pull "$model"
done

echo "--------------------------------------------------------"
echo "All requested models have been pulled successfully!"
echo "Available models in Ollama:"
docker exec "$CONTAINER_NAME" ollama list
