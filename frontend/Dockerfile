# Multi-stage build for Cardano dApp Frontend

# Stage 1: Build the frontend (supporting multi-arch)
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
FROM --platform=$BUILDPLATFORM node:23.10.0 AS builder

RUN echo "Building on $BUILDPLATFORM for $TARGETPLATFORM ($TARGETOS/$TARGETARCH)"

# Install required system dependencies (including build tools for native modules)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      curl \
      python3 \
      make \
      g++ \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./

# Install dependencies with network-friendly settings
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm ci --prefer-offline --no-audit --unsafe-perm

COPY . .

# `build:prod`, NU `build`. Cel din urmă împachetează `MainDemo`, adică interpretul DemoM cu date
# mock — e default-ul potrivit pentru `npm run dev` și pentru e2e, și e exact greșit pentru imaginea
# care ajunge în cluster. Template-ul avea aici `npm run build`, deci imaginea lui de producție
# servea fixturi. `build:prod` împachetează `Main`, care e AppM cu HTTP real.
RUN npm run build:prod

# Stage 2: Production server with Fastify only (multi-arch)
FROM node:23.10.0-alpine AS production

# Upgrade base OS packages to pick up security fixes
RUN apk -U --no-cache upgrade && \
    apk add --no-cache wget

WORKDIR /app

# Minimal package.json for BFF (avoids module-type warning at runtime)
RUN echo '{"type":"module"}' > package.json

# Install only BFF dependencies (not PureScript, vite, etc.)
RUN npm install --omit=dev --prefer-offline --no-audit \
    fastify@^5.1.0 \
    @fastify/cors@^10.0.1 \
    @fastify/http-proxy@^11.1.1 \
    @fastify/static@^8.0.1

# Copy built frontend + BFF
COPY --from=builder /app/dist ./dist
COPY bff/ ./bff/
COPY bff/start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

CMD ["/app/start.sh"]
