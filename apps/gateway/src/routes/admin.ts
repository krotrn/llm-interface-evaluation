import { FastifyInstance } from 'fastify';
import { flushCache } from '../services/cache.js';

export default async function adminRoutes(fastify: FastifyInstance) {
  fastify.delete(
    '/v1/cache',
    {
      preValidation: [fastify.authenticate],
    },
    async (request, reply) => {
      const entriesCleared = await flushCache(fastify.pg, fastify.redis);
      return reply.status(200).send({
        status: 'ok',
        entries_cleared: entriesCleared,
        request_id: request.id,
      });
    }
  );
}
