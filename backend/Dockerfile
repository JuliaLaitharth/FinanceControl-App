# ── Etapa 1: build ───────────────────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

# O Prisma precisa do OpenSSL no Alpine para detectar a versão da libssl.
RUN apk add --no-cache openssl

COPY package*.json ./
RUN npm ci

COPY . .
# Gera o cliente já com o esquema presente (o postinstall do npm ci roda sem ele).
RUN npx prisma generate && npm run build

# ── Etapa 2: produção ─────────────────────────────────────────────────────────
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
RUN apk add --no-cache openssl

COPY package*.json ./
RUN npm ci --omit=dev

# Binário do Prisma compilado para a plataforma do container
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma

EXPOSE 3000

# Roda as migrations e então inicia o servidor
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/main"]
