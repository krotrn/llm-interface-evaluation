import { generate } from "./ollama-client.js";

async function main() {
  for await (const chunk of generate(
    "qwen3:4b",
    "Generate one word"
  )) {
    if (typeof chunk.response === "string") {
      process.stdout.write(chunk.response);
    }
  }
}

main().catch(console.error);