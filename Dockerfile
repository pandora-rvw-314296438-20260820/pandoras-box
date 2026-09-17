FROM node:24-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json .npmrc ./
COPY apps/meta-business-mcp/package.json ./apps/meta-business-mcp/package.json
COPY packages/shared-security/package.json ./packages/shared-security/package.json
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
COPY packages/shared-security ./packages/shared-security
COPY apps/meta-business-mcp ./apps/meta-business-mcp
RUN npm run build

FROM node:24-alpine AS runtime
RUN apk add --no-cache dumb-init \
    && addgroup -S meta-mcp \
    && adduser -S -G meta-mcp meta-mcp
WORKDIR /app
ENV NODE_ENV=production \
    MCPMASTER_CONTAINER_MODE=pandora \
    MCPMASTER_CONTROL_TOWER_DIR=/app/apps/control-tower \
    MCPMASTER_RUNTIME_MODULE=/app/dist/http-app.js

COPY package.json package-lock.json .npmrc ./
COPY apps/meta-business-mcp/package.json ./apps/meta-business-mcp/package.json
COPY packages/shared-security/package.json ./packages/shared-security/package.json
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/packages/shared-security/dist ./packages/shared-security/dist
COPY --from=builder /app/apps/meta-business-mcp/dist ./apps/meta-business-mcp/dist
COPY apps/control-tower ./apps/control-tower
COPY public ./public

USER meta-mcp
EXPOSE 3000
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/container-entrypoint.js"]
