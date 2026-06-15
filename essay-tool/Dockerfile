# Essay Tool — production container
FROM node:22-slim AS base
WORKDIR /app
# OpenSSL is required by Prisma's query engine.
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

# Install dependencies (postinstall runs `prisma generate`).
COPY package.json package-lock.json* ./
COPY prisma ./prisma
RUN npm install

# Build the app.
COPY . .
RUN npm run build

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

# `start:prod` runs `prisma db push` (creates/updates the SQLite schema on the
# mounted volume) and then starts Next.js.
CMD ["npm", "run", "start:prod"]
