# https://github.com/umami-software/umami/blob/master/Dockerfile

FROM --platform=${BUILDPLATFORM} alpine as source

ENV VERSION=1.39.4

WORKDIR /tmp

RUN wget https://github.com/umami-software/umami/archive/refs/tags/v${VERSION}.tar.gz && \
    tar -xvf v${VERSION}.tar.gz && \
    rm v${VERSION}.tar.gz && \
    mv /tmp/umami-${VERSION} /src


WORKDIR /src

# Install dependencies only when needed
FROM node:16-slim AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
# RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY --from=source /src/package.json /src/yarn.lock ./
RUN yarn install --frozen-lockfile --network-timeout 600000

# Rebuild the source code only when needed
FROM node:16-slim AS builder
WORKDIR /app
# RUN apk add --no-cache openssl

COPY --from=deps /app/node_modules ./node_modules
COPY --from=source /src .

ARG DATABASE_URL
ARG DATABASE_TYPE
ARG BASE_PATH
ARG DISABLE_LOGIN

ENV DATABASE_URL $DATABASE_URL
ENV DATABASE_TYPE $DATABASE_TYPE
ENV BASE_PATH $BASE_PATH
ENV DISABLE_LOGIN $DISABLE_LOGIN

ENV NEXT_TELEMETRY_DISABLED 1

RUN yarn build-docker

# Production image, copy all the files and run next
FROM node:16-slim AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

RUN yarn add npm-run-all dotenv prisma
# RUN apk add --no-cache openssl

# You only need to copy next.config.js if you are NOT using the default configuration
COPY --from=builder /app/next.config.js .
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT 3000

CMD ["yarn", "start-docker"]
