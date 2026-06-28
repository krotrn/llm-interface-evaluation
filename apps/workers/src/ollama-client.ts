const baseUrl = process.env.OLLAMA_BASE_URL || "http://localhost:11434";

export async function* generate(
  model: string,
  prompt: string,
  options: Record<string, unknown> = {}
): AsyncGenerator<{ response: string; done: boolean }> {
  const res = await fetch( baseUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      prompt,
      options,
    }),
  });

  if (!res.ok) {
    const errorText = await res.text().catch(() => "");
    throw new Error(`Ollama API returned status ${res.status}: ${errorText}`);
  }

  if (!res.body) {
    throw new Error("No response body");
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();

  try{
  let buffer = "";

  while (true) {
    const { value, done } = await reader.read();

    if (done) break;

    buffer += decoder.decode(value, { stream: true });
  
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      if (!line.trim()) continue;
      yield JSON.parse(line);
    }
  }

  if (buffer.trim()) {
    yield JSON.parse(buffer);
  }
}finally{
   reader.releaseLock();
}
}
