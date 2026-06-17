#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Run the python validation script inside the running embedding container
docker compose exec -T embedding python3 - <<'EOF'
import json
import urllib.request
import sys

url = "http://localhost:8000/embed"

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
if sim_1_2 <= 0.85:
    print("FAIL: similarity between Q1 and Q2 should be > 0.85")
    success = False
else:
    print("PASS: similarity between Q1 and Q2 > 0.85")

if sim_1_3 >= 0.5:
    print("FAIL: similarity between Q1 and Q3 should be < 0.5")
    success = False
else:
    print("PASS: similarity between Q1 and Q3 < 0.5")

if not success:
    sys.exit(1)
print("All checks passed successfully!")
EOF