ARG BASE_IMAGE="debian:12.8-slim@sha256:1537a6a1cbc4b4fd401da800ee9480207e7dc1f23560c21259f681db56768f63"

FROM ${BASE_IMAGE} as build-image

ARG RCLONE_VERSION="v1.68.2"
ARG RESTIC_VERSION="0.17.3"
ARG DOCKER_VERSION="27.3.1"

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
    && apt-get clean

# get rclone and restic from build-image
COPY --from=build-image /bin/rclone /bin/rclone
COPY --from=build-image /bin/restic /bin/restic
COPY --from=build-image /tmp/docker /usr/local/bin/docker

RUN mkdir -p /local /var/log/restic \
    && touch /var/log/cron.log \
    && touch /var/log/restic/backup.log \
    && touch /var/log/restic/lastrun.log \
    && chmod +x /bin/rclone /bin/restic /usr/local/bin/docker

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY entry.sh /bin/entry.sh
COPY log.sh /bin/log.sh
COPY pre-default.sh /bin/pre-default.sh
RUN chmod +x /bin/backup /bin/check /bin/entry.sh /bin/log.sh /bin/pre-default.sh

ENTRYPOINT ["/bin/entry.sh"]
CMD ["cron", "-f", "-L", "2"]
