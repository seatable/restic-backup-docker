FROM alpine:latest as rclone

# Get rclone executable
ADD https://downloads.rclone.org/rclone-current-linux-amd64.zip /
RUN unzip rclone-current-linux-amd64.zip && mv rclone-*-linux-amd64/rclone /bin/rclone && chmod +x /bin/rclone

FROM restic/restic:0.16.4

RUN apk add --update --no-cache curl mailx docker openssl tree bash

COPY --from=rclone /bin/rclone /bin/rclone

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