import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import crypto from 'crypto';
import redisPlugin from './plugins/redis.js';
import postgresPlugin from './plugins/postgres.js';
import authPlugin from './plugins/auth.js';
import healthRoutes from './routes/health.js';
import adminRoutes from './routes/admin.js';
import { logger } from './services/logger.js';

export async function buildApp() {
  const app = Fastify({
    loggerInstance: logger,
    disableRequestLogging: true, // We can customize request logging if needed
    genReqId: (req) => {
      const header = req.headers['x-request-id'];
      if (header) {
        const id = Array.isArray(header) ? header[0] : header;
        if (id) return id;
      }
      return crypto.randomUUID();
    },
  });

  // Register standard HTTP error helpers first
  await app.register(sensible);

  // Register Auth plugin (requires sensible)
  await app.register(authPlugin);

  // Register Redis connection plugin
  await app.register(redisPlugin);

  // Register Postgres connection pool plugin
  await app.register(postgresPlugin);

  // Add global hook to inject X-Request-Id header on all responses
  app.addHook('onSend', async (request, reply, payload) => {
    reply.header('X-Request-Id', request.id);
    return payload;
  });

  // Register Route handlers
  await app.register(healthRoutes);
  await app.register(adminRoutes);

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
