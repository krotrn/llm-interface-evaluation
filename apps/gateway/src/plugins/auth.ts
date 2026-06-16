import { FastifyInstance, FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import fp from 'fastify-plugin';
import { logger } from '../services/logger.js';

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
  interface FastifyRequest {
    apiKey?: string;
  }
}

const authPlugin: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // We expect @fastify/sensible to be registered first, which provides fastify.httpErrors.
  // In case it's not, we'll verify it or throw a helper.

  const authenticate = async (request: FastifyRequest, reply: FastifyReply) => {
    const apiKeyHeader = request.headers['x-api-key'];

    if (!apiKeyHeader) {
      logger.warn({ ip: request.ip }, 'Authentication failed: Missing X-API-Key header');
      throw fastify.httpErrors.unauthorized('API key is missing');
    }

    const apiKey = Array.isArray(apiKeyHeader) ? apiKeyHeader[0] : apiKeyHeader;

    if (!apiKey) {
      logger.warn({ ip: request.ip }, 'Authentication failed: Empty X-API-Key header');
      throw fastify.httpErrors.unauthorized('API key is missing');
    }

    const configuredKeys = (process.env.API_KEYS || '')
      .split(',')
      .map((key) => key.trim())
      .filter(Boolean);

    if (!configuredKeys.includes(apiKey)) {
      logger.warn({ ip: request.ip }, 'Authentication failed: Invalid API key');
      throw fastify.httpErrors.unauthorized('Invalid API key');
    }

    // Attach the validated key to the request context
    request.apiKey = apiKey;
  };

  fastify.decorate('authenticate', authenticate);
};

export default fp(authPlugin, {
  name: 'auth',
  dependencies: ['@fastify/sensible'],
});
