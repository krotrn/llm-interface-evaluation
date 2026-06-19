import { logger } from './logger.js';

export class EmbeddingError extends Error {
  constructor(message: string, public readonly originalError?: Error) {
    super(message);
    this.name = 'EmbeddingError';
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

const EMBEDDING_TIMEOUT_MS = parseInt(process.env.EMBEDDING_TIMEOUT_MS || '5000', 10);

/**
 * Generates an embedding for the given text using the external embedding service.
 * Converts the returned number array to a Float32Array of length 384.
 * Handles timeouts and service down errors by throwing an EmbeddingError.
 */
export async function embed(text: string, timeoutMs: number = EMBEDDING_TIMEOUT_MS): Promise<Float32Array> {
  const embeddingServiceUrl = process.env.EMBEDDING_SERVICE_URL || 'http://localhost:8000';
  const url = `${embeddingServiceUrl}/embed`;

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ text }),
      signal: AbortSignal.timeout(timeoutMs),
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      throw new Error(`Embedding service returned status ${response.status}: ${errorText}`);
    }

    const data: {
      embedding: number[];
      model: string;
      latency_ms: number;
    } = await response.json();

    if (!data || !Array.isArray(data.embedding)) {
      throw new Error('Invalid response structure from embedding service: missing embedding array');
    }

    if (data.embedding.length !== 384) {
      throw new Error(`Invalid embedding length: expected 384, got ${data.embedding.length}`);
    }

    return new Float32Array(data.embedding);
  } catch (error) {
    let message = error instanceof Error ? error.message : String(error);
    
    if (error instanceof Error) {
      const isTimeout = error.name === 'TimeoutError' || (error instanceof DOMException && error.name === 'TimeoutError');
      const errorCode = Reflect.get(error, 'code');
      const isConnectionRefused = errorCode === 'ECONNREFUSED' || error.message.includes('fetch failed');
      
      if (isTimeout) {
        message = `Embedding request timed out after ${timeoutMs}ms`;
      } else if (isConnectionRefused) {
        message = `Embedding service connection failed: ${error.message}`;
      }
    }
    
    const embeddingError = new EmbeddingError(
      message,
      error instanceof Error ? error : new Error(message)
    );
    logger.error({ err: embeddingError, text }, 'Embedding service client error');
    throw embeddingError;
  }
}
