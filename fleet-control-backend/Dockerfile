# =============================================================================
# Backend Node.js — SGV Sistema de Gestão de Viaturas
# =============================================================================
FROM node:18-alpine

# Healthcheck tool
RUN apk add --no-cache curl

WORKDIR /app

# --- Dependências (usa cache do Docker) ---
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# --- Código da aplicação ---
COPY . .

# Segurança: roda como usuário não-root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 3000

# Healthcheck para o Easypanel/container orchestrator
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/ || exit 1

CMD ["node", "server.js"]