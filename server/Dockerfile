FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY server ./server
RUN mkdir -p /data && chown node:node /data
USER node
ENV PORT=3001 DB_PATH=/data/pong.sqlite
EXPOSE 3001
CMD ["node", "server/index.js"]
