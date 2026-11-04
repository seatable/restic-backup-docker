# Pinned so a rebuild of the same commit produces the same base; bump deliberately.
# `apk upgrade` below still pulls Alpine security fixes.
ARG BASE_IMAGE="alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a"
ARG GO_IMAGE="golang:1.26.10-alpine3.24@sha256:a2012b4a1d1f9f7e9f44e0d39b805a901e856b1dd80b4e6ee4338db547050308"

# restic and rclone are built from their release tags with a current Go toolchain, because the upstream
# release binaries carry the CVEs of the Go version and modules they were built with. The module bumps below are the
# minimum to fix known CVEs. Review them with every version bump and remove those the new release already contains.
FROM ${GO_IMAGE} AS restic-build
ARG RESTIC_VERSION="0.19.1"
ARG RESTIC_COMMIT="6aa3a516ce654808a1f28f9fa21e9b7c8e6e90bf"
ENV GOTOOLCHAIN=local CGO_ENABLED=0
RUN apk add --no-cache git \
    && git clone --depth 1 --branch "v${RESTIC_VERSION}" https://github.com/restic/restic /src \
    && test "$(git -C /src rev-parse HEAD)" = "${RESTIC_COMMIT}"
WORKDIR /src
RUN go get \
        golang.org/x/net@v0.62.0 \
        golang.org/x/text@v0.43.0 \
        golang.org/x/crypto@v0.58.0 \
        google.golang.org/grpc@v1.85.0 \
        github.com/klauspost/compress@v1.18.7 \
        go.opentelemetry.io/otel/sdk@v1.45.0 \
        github.com/go-jose/go-jose/v4@v4.1.6 \
    && go mod tidy \
    && go build -trimpath -ldflags "-s -w" -o /out/restic ./cmd/restic

FROM ${GO_IMAGE} AS rclone-build
ARG RCLONE_VERSION="v1.75.2"
ARG RCLONE_COMMIT="be8d6044eacb843b74d335db0c5fbe09222031fe"
ENV GOTOOLCHAIN=local CGO_ENABLED=0
RUN apk add --no-cache git \
    && git clone --depth 1 --branch "${RCLONE_VERSION}" https://github.com/rclone/rclone /src \
    && test "$(git -C /src rev-parse HEAD)" = "${RCLONE_COMMIT}"
WORKDIR /src
RUN go get \
        golang.org/x/net@v0.62.0 \
        golang.org/x/crypto@v0.58.0 \
        github.com/go-chi/chi/v5@v5.4.0 \
    && go mod tidy \
    && go build -trimpath -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=${RCLONE_VERSION}" -o /out/rclone .

FROM ${BASE_IMAGE} AS docker-download
ARG DOCKER_VERSION="29.9.3"
ADD https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz /
RUN tar --extract --file docker-${DOCKER_VERSION}.tgz --directory /tmp/ --strip-components 1

FROM ${BASE_IMAGE} AS runtime-image

# coreutils: GNU date -d and timeout; flock: flock -E (both missing or limited in busybox)
RUN apk upgrade --no-cache \
    && apk add --no-cache \
        bash \
        ca-certificates \
        coreutils \
        cronie \
        curl \
        flock \
        gzip \
        jq \
        msmtp \
        openssh-client-default \
        procps \
        tree \
        tzdata

COPY --from=restic-build /out/restic /bin/restic
COPY --from=rclone-build /out/rclone /bin/rclone
COPY --from=docker-download /tmp/docker /usr/local/bin/docker

# output the versions (to check, that the expected versions are installed)
RUN /bin/restic version && /bin/rclone --version

RUN mkdir -p /local /var/log/restic \
    && touch /var/log/cron.log \
    && touch /var/log/restic/backup.log \
    && touch /var/log/restic/lastrun.log \
    && chmod +x /bin/rclone /bin/restic /usr/local/bin/docker

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY prune.sh /bin/prune
COPY functions.sh /bin/functions.sh
COPY entry.sh /bin/entry.sh
COPY log.sh /bin/log.sh
COPY pre-default.sh /bin/pre-default.sh
COPY cron-run.sh /bin/cron-run
COPY version /version
RUN chmod +x /bin/backup /bin/check /bin/prune /bin/entry.sh /bin/log.sh /bin/functions.sh /bin/pre-default.sh /bin/cron-run

ENTRYPOINT ["/bin/entry.sh"]
CMD ["crond", "-n"]
