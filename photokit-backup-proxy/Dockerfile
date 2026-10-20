FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV CONFIG_PATH=/config/config.json
LABEL org.opencontainers.image.source="https://github.com/TinusNL/iOS-PhotoKit-Backup"
LABEL org.opencontainers.image.description="PhotoKit background upload proxy"
COPY --from=build /app/dist ./dist
EXPOSE 8080
CMD ["node", "dist/index.js"]
