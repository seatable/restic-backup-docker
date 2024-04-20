ARG BASE_IMAGE="debian:12.5-slim@sha256:3d5df92588469a4c503adbead0e4129ef3f88e223954011c2169073897547cac"

FROM ${BASE_IMAGE} as build-image

ARG RCLONE_VERSION="v1.66.0"
ARG RESTIC_VERSION="0.16.4"
ARG DOCKER_VERSION="26.0.2"

RUN apt-get update && apt-get install --no-install-recommends -y \
unzip \
bzip2 \
curl

# Get rclone binary
ADD https://github.com/rclone/rclone/releases/download/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip /
RUN unzip rclone-${RCLONE_VERSION}-linux-amd64.zip && mv rclone-*-linux-amd64/rclone /bin/rclone && chmod +x /bin/rclone

# Get restic binary binary
ADD https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2 /
RUN bzip2 -v --decompress restic_${RESTIC_VERSION}_linux_amd64.bz2 && mv restic_*_linux_amd64 /bin/restic && chmod +x /bin/restic

# Get docker binary 
ADD https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz /
RUN tar --extract --file /tmp/docker-${DOCKER_VERSION}.tgz --directory /tmp/ --strip-components 1 && rm /tmp/docker.tgz

FROM ${BASE_IMAGE} as runtime-image

RUN \
    apt-get update \
    && apt-get install --no-install-recommends -y \
        curl \
        openssl \
        mailutils \
        bsd-mailx \
        tree \
        fuse \
        cron \
    && apt-get clean

# option 1
# works but probably to big?
#RUN curl -fsSL get.docker.com | bash

# option 2
#RUN apt-get install -y \
#    apt-transport-https ca-certificates gnupg lsb-release \
#    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
#    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
#       | tee /etc/apt/sources.list.d/docker.list > /dev/null \
#    && apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io \
#    && apt-get clean

# option 3
# get rclone and restic from build-image
COPY --from=build-image /bin/rclone /bin/rclone
COPY --from=build-image /bin/restic /bin/restic
COPY --from=build-image /tmp/docker /usr/local/bin/docker

RUN mkdir -p /local /var/spool/cron/crontabs /var/log \
    && touch /var/log/cron.log \
    && chmod +x /bin/rclone /bin/restic /usr/local/bin/docker

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY entry.sh /entry.sh
COPY pre-default.sh /bin/pre-default.sh

ENTRYPOINT ["/entry.sh"]
CMD ["tail","-fn0","/var/log/cron.log"]
