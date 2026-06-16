#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

OLLAMA_URL="http://localhost:11434"

# Models to test
MODELS=(
  "qwen2.5:3b"
  "qwen2.5:1.5b"
  "phi3:mini"
  "llama3.2:3b"
)

echo "Testing Ollama models via API..."
PASS_COUNT=0

for model in "${MODELS[@]}"; do
  echo -n "Testing model '$model'... "
  
  # Send generation request
  RESPONSE=$(curl -s -X POST "$OLLAMA_URL/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$model\", \"prompt\": \"Say hello in one word.\", \"stream\": false}")
  
  # Extract response field
  TEXT=$(echo "$RESPONSE" | grep -o '"response":"[^"]*"' | cut -d':' -f2 | tr -d '"')
  
  if [ -n "$TEXT" ]; then
    echo -e "\033[0;32mPASS\033[0m (Response: '$TEXT')"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "\033[0;31mFAIL\033[0m"
    echo "Full API Response: $RESPONSE"
  fi
done

echo "--------------------------------------------------------"
if [ $PASS_COUNT -eq ${#MODELS[@]} ]; then
  echo -e "\033[0;32m${PASS_COUNT}/${#MODELS[@]} PASS\033[0m"
  exit 0
else
  echo -e "\033[0;31m${PASS_COUNT}/${#MODELS[@]} PASS\033[0m"
  exit 1
fi
