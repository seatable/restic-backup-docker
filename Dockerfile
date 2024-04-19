ARG BASE_IMAGE="debian:12.5-slim@sha256:3d5df92588469a4c503adbead0e4129ef3f88e223954011c2169073897547cac"

FROM ${BASE_IMAGE} as build-image

ARG RCLONE_VERSION="v1.66.0"
ARG RESTIC_VERSION="0.16.4"

RUN apt-get update && apt-get install -y \
unzip \
bzip2

# Download / Uncompress and put the rclone binary in place
ADD https://github.com/rclone/rclone/releases/download/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-amd64.zip && mv rclone-*-linux-amd64/rclone /bin/rclone && chmod +x /bin/rclone

# Download / Uncompress and put the restic binary in place
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2 /
RUN bzip2 -v --decompress restic_${RESTIC_VERSION}_linux_amd64.bz2 && mv restic_*_linux_amd64 /bin/restic && chmod +x /bin/restic


FROM ${BASE_IMAGE} as runtime-image

#RUN apk add --update --no-cache curl mailx docker openssl tree bash

RUN apt-get update && apt-get install -y \
curl \
docker \
openssl \
mailutils \
bsd-mailx \
tree \
fuse \
cron

COPY --from=build-image /bin/rclone /bin/rclone
COPY --from=build-image /bin/restic /bin/restic

RUN \
    mkdir -p /local /var/spool/cron/crontabs /var/log; \
    touch /var/log/cron.log;

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY entry.sh /entry.sh
COPY pre-default.sh /bin/pre-default.sh

ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0","/var/log/cron.log"]
