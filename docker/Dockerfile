# ---- build stage ----
FROM node:18-alpine AS build
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --only=production

# ---- runtime stage ----
FROM node:18-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY app/ ./
ENV NODE_ENV=production
ENV PORT=8000
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8000/ || exit 1
CMD ["node", "src/server.js"]
