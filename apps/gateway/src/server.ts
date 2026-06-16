import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import redisPlugin from './plugins/redis.js';
import postgresPlugin from './plugins/postgres.js';
import authPlugin from './plugins/auth.js';
import healthRoutes from './routes/health.js';
import { logger } from './services/logger.js';

export async function buildApp() {
  const app = Fastify({
    logger,
    disableRequestLogging: true, // We can customize request logging if needed
  });

  // Register standard HTTP error helpers first
  await app.register(sensible);

  // Register Auth plugin (requires sensible)
  await app.register(authPlugin);

  // Register Redis connection plugin
  await app.register(redisPlugin);

  // Register Postgres connection pool plugin
  await app.register(postgresPlugin);

  // Register Route handlers
  await app.register(healthRoutes);

  return app;
}

export async function start() {
  const app = await buildApp();
  const port = parseInt(process.env.GATEWAY_PORT || '3000', 10);
  const host = process.env.GATEWAY_HOST || '0.0.0.0';

  try {
    await app.listen({ port, host });
    logger.info(`Gateway server is running on http://${host}:${port}`);
  } catch (err) {
    logger.error({ err }, 'Failed to start gateway server');
    process.exit(1);
  }
}
