ARG BASE_IMAGE="debian:12.10-slim@sha256:5accafaaf0f2c0a3ee5f2dcd9a5f2ef7ed3089fe4ac6a9fc9b1cf16396571322"

FROM ${BASE_IMAGE} as build-image

ARG RCLONE_VERSION="v1.69.2"
ARG RESTIC_VERSION="0.18.0"
ARG DOCKER_VERSION="28.1.1"
ENV SUPERCRONIC_VERSION="v0.2.33"

RUN apt-get update && apt-get install --no-install-recommends -y \
unzip \
bzip2 \
curl

# Get rclone binary
ADD https://github.com/rclone/rclone/releases/download/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-amd64.zip && mv rclone-*-linux-amd64/rclone /bin/rclone

# Get restic binary binary
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2 /
RUN bzip2 -v --decompress restic_${RESTIC_VERSION}_linux_amd64.bz2 && mv restic_*_linux_amd64 /bin/restic

# Get docker binary 
ADD https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz /
RUN tar --extract --file docker-${DOCKER_VERSION}.tgz --directory /tmp/ --strip-components 1

FROM ${BASE_IMAGE} as runtime-image

ARG USER_ID=1000
ARG GROUP_ID=1000

RUN groupadd -g ${GROUP_ID} appuser && \
    useradd -u ${USER_ID} -g appuser -s /bin/sh -d /home/appuser appuser && \
    mkdir -p /home/appuser && \
    chown -R appuser:appuser /home/appuser

RUN \
    apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends -y \
        curl \
        openssl \
        mailutils \
        msmtp \
        tree \
        fuse \
        ca-certificates \
        gzip \
        jq \
        openssh-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install supercronic (instead of cron)
RUN curl -fsSLO "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" && \
    chmod +x supercronic-linux-amd64 && \
    mv supercronic-linux-amd64 /usr/local/bin/supercronic

COPY --from=build-image /bin/rclone /bin/rclone
COPY --from=build-image /bin/restic /bin/restic
COPY --from=build-image /tmp/docker /usr/local/bin/docker

RUN mkdir -p /local /var/log/restic /var/spool/cron/crontabs && \
    touch /var/log/cron.log /var/log/restic/backup.log /var/log/restic/lastrun.log && \
    chown -R appuser:appuser /local /var/log /var/spool/cron/crontabs && \
    chmod +x /bin/rclone /bin/restic /usr/local/bin/docker

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY entry.sh /bin/entry.sh
COPY log.sh /bin/log.sh
COPY pre-default.sh /bin/pre-default.sh
COPY crontab /var/spool/cron/crontabs/appuser

RUN chmod +x /bin/backup /bin/check /bin/entry.sh /bin/log.sh /bin/pre-default.sh && \
    chown appuser:appuser /var/spool/cron/crontabs/appuser && \
    chmod 600 /var/spool/cron/crontabs/appuser

VOLUME /data

USER appuser:appuser
ENTRYPOINT ["/bin/entry.sh"]
CMD ["supercronic", "/var/spool/cron/crontabs/appuser"]