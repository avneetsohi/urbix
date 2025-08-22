# --- deps-dev: install deps needed to BUILD the backend (includes dev deps) ---
FROM node:20-slim AS deps-dev
WORKDIR /app

# Copy workspace manifests + lockfile (root)
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
# Copy the backend's manifest so pnpm can resolve its graph
COPY apps/backend/package.json apps/backend/package.json

# Install (workspace-aware) only for backend and its deps
RUN corepack enable && corepack prepare pnpm@9 --activate \
  && pnpm install -w --filter ./apps/backend... --frozen-lockfile

# --- build: compile TypeScript using dev deps ---
FROM node:20-slim AS build
WORKDIR /app

# Reuse installed deps
COPY --from=deps-dev /app/node_modules ./node_modules
COPY --from=deps-dev /app/apps/backend/package.json ./apps/backend/package.json

# Copy source and tsconfig
COPY apps/backend/tsconfig.json apps/backend/tsconfig.json
COPY apps/backend/src apps/backend/src

# Build (emits to apps/backend/dist)
RUN corepack enable && corepack prepare pnpm@9 --activate \
  && pnpm -C apps/backend add -D typescript \
  && pnpm -C apps/backend run build

# --- deps-prod: do clean PRODUCTION installs (root + backend) ---
FROM node:20-slim AS deps-prod
WORKDIR /app

COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY apps/backend/package.json apps/backend/package.json

RUN corepack enable && corepack prepare pnpm@9 --activate \
  # 1) lockfile-resolved prod deps at workspace root
  && pnpm install -w --prod --frozen-lockfile \
  # 2) ensure package-local node_modules exists for backend (symlinks to root store)
  && pnpm -C apps/backend install --prod --frozen-lockfile

# --- runtime: compiled code + prod deps only ---
FROM node:20-slim
ENV NODE_ENV=production

# Run from the backend package dir
WORKDIR /app/apps/backend

# Copy compiled app into the package dir
COPY --from=build /app/apps/backend/dist ./dist

# IMPORTANT: copy BOTH node_modules trees
# 1) Root store used by pnpm symlinks
COPY --from=deps-prod /app/node_modules /app/node_modules
# 2) Package-local node_modules that links into the root store
COPY --from=deps-prod /app/apps/backend/node_modules ./node_modules

# Minimal package.json so Node sees correct package boundary & "type": "module"
COPY apps/backend/package.json ./package.json

EXPOSE 8080
CMD ["node", "dist/index.js"]