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

// Local stub for Prometheus counters (to be integrated with prom-client in P1.3.6)
export const cacheHitsCounter = {
  value: 0,
  inc() {
    this.value++;
  }
};

export const cacheMissesCounter = {
  value: 0,
  inc() {
    this.value++;
  }
};

/**
 * Looks up a prompt embedding in the semantic cache.
 * 
 * 1. Queries PostgreSQL for the closest entry of the specified model within expiration time
 *    using negative inner product (<#>) on pgvector, matching the HNSW index design.
 * 2. Checks if the similarity score (-distance) meets CACHE_SIM_THRESHOLD.
 * 3. If the threshold is met, fetches the full prompt, response and metadata from Redis.
 * 4. Asynchronously increments hit count in both Postgres and Redis.
 * 
 * Returns the cached response object with similarity if hit, or null if miss.
 */
export async function lookupCache(
  pgPool: pg.Pool,
  redis: Redis,
  embedding: number[] | Float32Array,
  model: string
): Promise<{
  prompt: string;
  response: string;
  model: string;
  created_at: string;
  similarity: number;
} | null> {
  const threshold = parseFloat(process.env.CACHE_SIM_THRESHOLD || '0.92');
  const embeddingStr = `[${Array.from(embedding).join(',')}]`;

  logger.debug({ model }, 'Starting semantic cache lookup');

  // Query Postgres for closest vector
  let entryId: string;
  let similarity: number;

  try {
    const res = await pgPool.query(
      `SELECT id, - (embedding <#> $1::vector) AS similarity
       FROM cache_entries
       WHERE model = $2
         AND expires_at > NOW()
       ORDER BY embedding <#> $1::vector ASC
       LIMIT 1`,
      [embeddingStr, model]
    );

    if (res.rows.length === 0) {
      logger.debug({ model }, 'No cache entries found for model');
      cacheMissesCounter.inc();
      return null;
    }

    const row = res.rows[0];
    similarity = parseFloat(row.similarity);
    entryId = row.id.toString();

    logger.debug({ entryId, similarity, threshold }, 'Closest cache entry evaluated');

    if (similarity < threshold) {
      logger.debug({ entryId, similarity, threshold }, 'Cache miss: similarity below threshold');
      cacheMissesCounter.inc();
      return null;
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed Postgres cache query: ${message}`);
    cacheMissesCounter.inc();
    return null;
  }

  // Fetch response from Redis
  try {
    const cacheKey = `llmforge:cache:${entryId}`;
    const cached = await redis.hgetall(cacheKey);

    if (!cached || !cached.response || !cached.prompt || !cached.model || !cached.created_at) {
      logger.warn({ entryId }, 'Cache index hit in Postgres, but Redis key is missing fields or expired');
      cacheMissesCounter.inc();
      return null;
    }

    // Increment hit counts asynchronously (fire-and-forget)
    redis.hincrby(cacheKey, 'hit_count', 1).catch((err) => {
      logger.error({ err, entryId }, 'Failed to increment Redis cache hit count');
    });
    
    pgPool.query(
      `UPDATE cache_entries SET hit_count = hit_count + 1 WHERE id = $1`,
      [entryId]
    ).catch((err) => {
      logger.error({ err, entryId }, 'Failed to increment Postgres cache hit count');
    });

    logger.info({ entryId, similarity }, 'Semantic cache hit');
    cacheHitsCounter.inc();

    return {
      prompt: cached.prompt,
      response: cached.response,
      model: cached.model,
      created_at: cached.created_at,
      similarity,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err, entryId }, `Failed Redis cache lookup: ${message}`);
    cacheMissesCounter.inc();
    return null;
  }
}

/**
 * Flushes all semantic cache entries from PostgreSQL and Redis.
 * Deletes all rows from cache_entries table and removes all corresponding llmforge:cache:* Redis keys.
 */
export async function flushCache(
  pgPool: pg.Pool,
  redis: Redis
): Promise<void> {
  logger.info('Flushing semantic cache...');

  // 1. Delete all rows from Postgres cache_entries
  try {
    const res = await pgPool.query('DELETE FROM cache_entries');
    logger.info({ rowCount: res.rowCount }, 'Cleared Postgres cache_entries table');
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed to clear Postgres cache_entries: ${message}`);
    throw err;
  }

  // 2. Scan and delete keys matching llmforge:cache:* from Redis
  try {
    let cursor = '0';
    let totalDeleted = 0;
    do {
      const [nextCursor, keys] = await redis.scan(
        cursor,
        'MATCH',
        'llmforge:cache:*',
        'COUNT',
        100
      );
      cursor = nextCursor;
      if (keys.length > 0) {
        await redis.del(...keys);
        totalDeleted += keys.length;
      }
    } while (cursor !== '0');
    logger.info({ totalDeleted }, 'Cleared Redis cache keys');
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed to clear Redis cache keys: ${message}`);
    throw err;
  }
}

/**
 * Returns cache statistics: size (Postgres rows), hitCount (global), missCount (global).
 */
export async function getCacheStats(
  pgPool: pg.Pool,
  redis: Redis
): Promise<{ size: number; hitCount: number; missCount: number }> {
  try {
    const res = await pgPool.query('SELECT COUNT(*) FROM cache_entries');
    const size = parseInt(res.rows[0].count, 10);
    return {
      size,
      hitCount: cacheHitsCounter.value,
      missCount: cacheMissesCounter.value,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed to get cache stats: ${message}`);
    throw err;
  }
}

/**
 * Deletes expired cache entries from Postgres and deletes corresponding Redis keys.
 */
export async function evictExpiredCache(
  pgPool: pg.Pool,
  redis: Redis
): Promise<number> {
  logger.debug('Running background cache eviction...');

  try {
    // 1. Delete expired rows from Postgres and return their IDs
    const res = await pgPool.query(
      `DELETE FROM cache_entries 
       WHERE expires_at < NOW() 
       RETURNING id`
    );

    const expiredIds = res.rows.map((row) => row.id.toString());

    if (expiredIds.length > 0) {
      logger.info({ count: expiredIds.length }, 'Found expired cache entries in Postgres. Evicting from Redis...');

      // 2. Delete corresponding keys from Redis in a pipeline
      const pipeline = redis.pipeline();
      for (const id of expiredIds) {
        pipeline.del(`llmforge:cache:${id}`);
      }
      
      const pipelineResults = await pipeline.exec();
      if (pipelineResults) {
        for (const [err] of pipelineResults) {
          if (err) throw err;
        }
      }

      logger.info({ count: expiredIds.length }, 'Successfully evicted expired cache entries from Postgres and Redis');
    } else {
      logger.debug('No expired cache entries found to evict');
    }

    return expiredIds.length;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Cache eviction job failed: ${message}`);
    throw err;
  }
}

/**
 * Starts the background eviction interval.
 */
export function startCacheEvictionJob(
  pgPool: pg.Pool,
  redis: Redis,
  intervalMs: number = 300000
): NodeJS.Timeout {
  logger.info({ intervalMs }, 'Starting background cache eviction job...');
  const interval = setInterval(() => {
    evictExpiredCache(pgPool, redis).catch((err) => {
      logger.error({ err }, 'Cache eviction interval execution failed');
    });
  }, intervalMs);
  return interval;
}
