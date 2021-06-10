# create a standard base image that has all the defaults
FROM node:14-buster-slim AS base
WORKDIR /app

ENV NODE_ENV=production
ENV PATH /app/node_modules/.bin:$PATH
ENV TINI_VERSION v0.19.0

RUN apt-get update && apt-get install -y openssl jq --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

COPY package*.json yarn.lock* ./
COPY db /app/db
RUN yarn config list \
    # yarn --production seems to be buggy, it pulls devDependencies. So let's just remove it from package.json for this stage
    && jq 'del(.devDependencies)' package.json > package.json.tmp && mv package.json.tmp package.json \
    && yarn install --production --frozen-lockfile \
    && npx next telemetry disable \
    && yarn cache clean --force \
    # saves a few Mb's
    && npm cache clean --force \
    # Prisma is caching engines in users .cache directory. There is no need for that in an image.
    && rm -rf /root/.cache

# create a build image
FROM base as build
ENV NODE_ENV=development

COPY . .
RUN yarn install --frozen-lockfile \
    && yarn next telemetry disable \
    && npx prisma generate \
    && blitz build

# create a production image
FROM base as production
ENV SESSION_SECRET_KEY="test tobe changed for production"
ENV DATABASE_URL="file:./db.sqlite"

ENV TZ=Europe/Berlin

COPY --from=build /app/db /app/db
COPY --from=build /app/.blitz /app/.blitz
COPY --from=build /app/node_modules/.prisma /app/node_modules/.prisma

# Copy config if necessary
# COPY --from=build /app/blitz.config.js /app/blitz.config.js

EXPOSE 3000
CMD npx blitz start

ENTRYPOINT ["/tini", "--"]
