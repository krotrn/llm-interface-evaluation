#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Run the python validation script inside the running embedding container
docker compose exec -T embedding python3 - <<'EOF'
import json
import urllib.request
import sys

# In docker network, ollama is resolved at 'ollama'
url = "http://ollama:11434/api/generate"

models = ["qwen2.5:3b", "qwen2.5:1.5b", "phi3:mini", "llama3.2:3b"]
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
