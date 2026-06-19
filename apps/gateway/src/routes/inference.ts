import { FastifyInstance, FastifyPluginAsync } from 'fastify';

interface InferenceRequestBody {
  prompt: string;
  model?: string;
  stream?: boolean;
  metadata?: Record<string, string | number | boolean | null | object>;
}

const inferenceRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.post<{ Body: InferenceRequestBody }>(
    '/v1/inference',
    {
      preValidation: [fastify.authenticate],
      schema: {
        body: {
          type: 'object',
          required: ['prompt'],
          properties: {
            prompt: {
              type: 'string',
              minLength: 1,
              maxLength: 8000,
              pattern: '^.*\\S.*$',
            },
            model: {
              type: 'string',
            },
            stream: {
              type: 'boolean',
            },
            metadata: {
              type: 'object',
            },
          },
          additionalProperties: false,
        },
      },
      errorHandler: (error, request, reply) => {
        if (error.validation && error.validation.length > 0) {
          const firstError = error.validation[0];
          if (firstError) {
            const rawField = firstError.instancePath.replace(/^\//, '');
            let field = rawField;

            if (!field && firstError.params && typeof firstError.params === 'object') {
              const params = firstError.params;
              if ('missingProperty' in params) {
                const missing = Reflect.get(params, 'missingProperty');
                if (typeof missing === 'string') {
                  field = missing;
                }
              }
            }
            
            let message = error.message;
            if (firstError.keyword === 'required') {
              message = `Field '${field}' is required and must be a non-empty string.`;
            } else if (firstError.keyword === 'pattern' || firstError.keyword === 'minLength') {
              message = `Field '${field}' must be a non-empty string.`;
            } else if (firstError.keyword === 'maxLength') {
              message = `Field '${field}' exceeds maximum length of 8000 characters.`;
            } else if (firstError.keyword === 'type') {
              message = `Field '${field}' has invalid type.`;
            }

            return reply.status(400).send({
              error: {
                code: 'validation_error',
                message,
                request_id: request.id,
                field,
              },
            });
          }
        }
        reply.send(error);
      },
    },
    async (request, reply) => {
      const { prompt, model, stream, metadata } = request.body;

      // 1. Validate model against allowed models in FALLBACK_MODEL_CHAIN
      const allowedModels = (process.env.FALLBACK_MODEL_CHAIN || 'qwen2.5:3b,qwen2.5:1.5b')
        .split(',')
        .map((m) => m.trim())
        .filter(Boolean);

      if (model && !allowedModels.includes(model)) {
        return reply.status(400).send({
          error: {
            code: 'validation_error',
            message: `Unknown model '${model}'. Allowed models are: ${allowedModels.join(', ')}`,
            request_id: request.id,
            field: 'model',
          },
        });
      }

      // 2. Validate metadata serialized size capped at 2KB
      if (metadata) {
        try {
          const serializedMetadata = JSON.stringify(metadata);
          if (serializedMetadata.length > 2048) {
            return reply.status(400).send({
              error: {
                code: 'validation_error',
                message: "Field 'metadata' serialized size exceeds 2KB limit.",
                request_id: request.id,
                field: 'metadata',
              },
            });
          }
        } catch (err) {
          return reply.status(400).send({
            error: {
              code: 'validation_error',
              message: "Field 'metadata' must be a valid JSON object.",
              request_id: request.id,
              field: 'metadata',
            },
          });
        }
      }

      return reply.status(200).send({
        status: 'ok',
        validated: true,
        body: { prompt, model, stream, metadata },
      });
    }
  );
};

export default inferenceRoutes;
