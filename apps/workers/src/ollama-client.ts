export async function* generate(
  model: string,
  prompt: string,
  options: Record<string, unknown> = {}
): AsyncGenerator<{ response: string; done: boolean }> {
  const res = await fetch("http://localhost:11434/api/generate", {
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

  if (!res.body) {
    throw new Error("No response body");
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();

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
}
