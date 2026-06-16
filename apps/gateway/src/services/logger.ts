import pino from 'pino';

const isProduction = process.env.NODE_ENV === 'production';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  mixin() {
    return { service: 'gateway' };
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  transport: !isProduction
    ? {
        target: 'pino-pretty',
        options: {
          colorize: true,
        },
      }
    : undefined,
});

export default logger;
