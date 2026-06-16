import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import fp from 'fastify-plugin';
import pg from 'pg';
import { logger } from '../services/logger.js';

declare module 'fastify' {
  interface FastifyInstance {
    pg: pg.Pool;
  }
}

const postgresPlugin: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/llmforge';

  logger.info('Initializing PostgreSQL connection pool...');

  const pool = new pg.Pool({
    connectionString,
    // Add reasonable pool sizing and timeouts
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
  });

  try {
    const client = await pool.connect();
    try {
      await client.query('SELECT 1');
      logger.info('Successfully connected to PostgreSQL and executed test query');
    } finally {
      client.release();
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed to connect to PostgreSQL: ${message}`);
    // Make sure we end the pool if connection verification failed
    await pool.end().catch(() => {});
    throw new Error(`Failed to connect to PostgreSQL: ${message}`);
  }

  fastify.decorate('pg', pool);

  fastify.addHook('onClose', async (instance) => {
    logger.info('Closing PostgreSQL connection pool...');
    await instance.pg.end();
  });
};

export default fp(postgresPlugin, {
  name: 'postgres',
});
