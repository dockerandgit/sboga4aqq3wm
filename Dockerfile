# Stage 1: Fetching utils
FROM ubuntu:22.04 AS utils
ENV DEBIAN_FRONTEND=noninteractive
COPY docker-utils/*.sh .
RUN chmod +x *.sh
RUN sh ./ffmpeg-fetch.sh
RUN sh ./fetch-twitchdownloader.sh

# Stage 2: Base image with Node.js
FROM ubuntu:22.04 AS base
ARG TARGETPLATFORM
ARG DEBIAN_FRONTEND=noninteractive
ENV UID=1000
ENV GID=1000
ENV USER=youtube
ENV NO_UPDATE_NOTIFIER=true
ENV PM2_HOME=/app/pm2
ENV ALLOW_CONFIG_MUTATIONS=true
ENV npm_config_cache=/app/.npm

# Use NVM to get specific Node version
ENV NODE_VERSION=16.14.2
RUN groupadd -g $GID $USER && useradd --system -m -g $USER --uid $UID $USER && \
    apt update && \
    apt install -y --no-install-recommends curl ca-certificates tzdata libicu70 libatomic1 && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /usr/local/nvm
ENV PATH="/usr/local/nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"
ENV NVM_DIR=/usr/local/nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}

# Stage 3: Build frontend
FROM node:16 AS frontend
RUN npm install -g @angular/cli
WORKDIR /build
COPY package.json package-lock.json angular.json tsconfig.json /build/
COPY src/ /build/src/
RUN npm install && npm run build

# Stage 4: Install backend dependencies
FROM base AS backend
WORKDIR /app
COPY backend/ /app/
RUN npm config set strict-ssl false && \
    npm install --prod

# Stage 5: Final image
FROM base
RUN npm install -g pm2 && \
    apt update && \
    apt install -y --no-install-recommends gosu python3-minimal python-is-python3 python3-pip atomicparsley build-essential && \
    pip install pycryptodomex && \
    apt remove -y --purge build-essential && \
    apt autoremove -y --purge && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Copy utilities, backend, and frontend build artifacts
COPY --from=utils /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=utils /usr/local/bin/ffprobe /usr/local/bin/ffprobe
COPY --from=utils /usr/local/bin/TwitchDownloaderCLI /usr/local/bin/TwitchDownloaderCLI
COPY --from=backend /app /app/
COPY --from=frontend /build/backend/public /app/public
COPY ./yt-dlp-youtube-oauth2.zip /app/node_modules/youtube-dl/bin/

RUN chmod +x /app/fix-scripts/*.sh

# Expose the port and define the entry point
EXPOSE 17442
ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD [ "npm", "start" ]
