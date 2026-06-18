import pg from 'pg';
import { Redis } from 'ioredis';
import crypto from 'crypto';
import { logger } from './logger.js';

/**
 * Generates sha256 hash of a string.
 */
function sha256(text: string): string {
  return crypto.createHash('sha256').update(text).digest('hex');
}

/**
 * Writes prompt embedding and response data to the semantic cache.
 * 
 * Inserts the embedding + metadata into PostgreSQL (returning the auto-generated bigint ID),
 * and stores the full prompt, response, and model metadata in Redis with a TTL.
 * 
 * Uses a Postgres transaction and a Redis pipeline.
 * Handles conflicts gracefully by updating the existing entry's embedding and expires_at.
 */
export async function writeCache(
  pgPool: pg.Pool,
  redis: Redis,
  prompt: string,
  embedding: number[] | Float32Array,
  response: string,
  model: string,
  ttlSeconds: number = 3600
): Promise<string> {
  const promptHash = sha256(prompt);
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000);
  const embeddingStr = `[${Array.from(embedding).join(',')}]`;

  logger.debug({ promptHash, model }, 'Attempting to write to semantic cache');

  let entryId: string;

  // 1. Write embedding + metadata to Postgres using a transaction
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    
    const res = await client.query(
      `INSERT INTO cache_entries (prompt_hash, embedding, model, expires_at)
       VALUES ($1, $2::vector, $3, $4)
       ON CONFLICT (prompt_hash, model) DO UPDATE SET
         embedding = EXCLUDED.embedding,
         expires_at = EXCLUDED.expires_at,
         hit_count = 0
       RETURNING id`,
      [promptHash, embeddingStr, model, expiresAt]
    );
    
    await client.query('COMMIT');
    entryId = res.rows[0].id.toString();
  } catch (err) {
    await client.query('ROLLBACK').catch((rollbackErr: unknown) => {
      logger.error({ err: rollbackErr }, 'Failed to rollback Postgres transaction');
    });
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed Postgres cache write: ${message}`);
    throw err;
  } finally {
    client.release();
  }

  // 2. Write response data to Redis using a pipeline
  try {
    const pipeline = redis.pipeline();
    const cacheKey = `llmforge:cache:${entryId}`;
    
    pipeline.hset(cacheKey, {
      prompt,
      response,
      model,
      created_at: new Date().toISOString(),
      hit_count: '0',
    });
    pipeline.expire(cacheKey, ttlSeconds);
    
    const results = await pipeline.exec();
    if (results) {
      for (const [err] of results) {
        if (err) throw err;
      }
    }
    logger.info({ entryId, promptHash, model }, 'Successfully wrote entry to semantic cache');
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err, entryId }, `Failed Redis cache write: ${message}`);
    throw err;
  }

  return entryId;
}
