ARG BASE_IMAGE="debian:12.15-slim@sha256:5ae3c39ebd15e229dcedd5cee596b2497182493d41ff162e824ba13fc1b2b867"

FROM ${BASE_IMAGE} as build-image

ARG RCLONE_VERSION="v1.75.1"
ARG RESTIC_VERSION="0.19.1"
ARG DOCKER_VERSION="29.8.0"

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
        cron \
        ca-certificates \
        gzip \
        jq \
        openssh-client \
        procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# get rclone and restic from build-image
COPY --from=build-image /bin/rclone /bin/rclone
COPY --from=build-image /bin/restic /bin/restic
COPY --from=build-image /tmp/docker /usr/local/bin/docker

# output rclone version (to check, that the latest version is installed)
RUN /bin/rclone --version

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
CMD ["cron", "-f", "-L", "2"]