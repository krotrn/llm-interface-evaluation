# Build stage
FROM oven/bun:alpine AS builder
WORKDIR /app

# Copy monorepo workspace configuration
COPY package.json bun.lock ./
COPY apps/gateway/package.json ./apps/gateway/package.json
COPY apps/workers/package.json ./apps/workers/package.json
COPY apps/eval/package.json ./apps/eval/package.json

# Install dependencies using Bun
RUN bun install

# Copy gateway source code
COPY apps/gateway ./apps/gateway

# Compile TypeScript gateway code
WORKDIR /app/apps/gateway
RUN bun run build

# Production runner stage
FROM node:24-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

# Copy built artifacts and dependencies from builder stage
COPY --from=builder --chown=node:node /app /app

# Run as non-root node user
USER node

# Expose gateway port
EXPOSE 3000

# Start gateway application
WORKDIR /app/apps/gateway
CMD ["node", "dist/index.js"]
