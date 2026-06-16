import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import fp from 'fastify-plugin';
import { Redis } from 'ioredis';
import { logger } from '../services/logger.js';

declare module 'fastify' {
  interface FastifyInstance {
    redis: Redis;
  }
}

const redisPlugin: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';

  logger.info({ redisUrl }, 'Initializing Redis client...');

  const redis = new Redis(redisUrl, {
    lazyConnect: true,
    maxRetriesPerRequest: 3, // fail fast on connection errors
    retryStrategy(times: number) {
      if (times > 3) {
        return null; // stop retrying
      }
      return Math.min(times * 100, 2000);
    },
  });

  try {
    await redis.connect();
    logger.info('Successfully connected to Redis');
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error({ err }, `Failed to connect to Redis: ${message}`);
    throw new Error(`Failed to connect to Redis: ${message}`);
  }

  fastify.decorate('redis', redis);

  fastify.addHook('onClose', async (instance) => {
    logger.info('Closing Redis connection...');
    await instance.redis.quit();
  });
};

export default fp(redisPlugin, {
  name: 'redis',
});
