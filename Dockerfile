# ===========================================
# Stage 1: Build
# ===========================================
FROM node:22-alpine AS builder

WORKDIR /app

COPY package.json package.json
RUN npm install

COPY tsconfig.json tsconfig.json
COPY src/ src/
RUN npm run build

# ===========================================
# Stage 2: Runtime
# ===========================================
FROM node:22-alpine AS runtime

WORKDIR /app

# 仅安装生产依赖
COPY package.json package.json
RUN npm install --omit=dev && npm cache clean --force

# 复制编译产物
COPY --from=builder /app/dist/ dist/

# 创建工作目录
RUN mkdir -p /workspace /tmp && \
    chown -R node:node /app /workspace /tmp

USER node

EXPOSE 8080

CMD ["node", "dist/server.js"]