# Restic Backup Docker Container

This Docker container automates restic backups and checks at regular intervals. It offers:

- Simple setup and maintanance
- Define backup and integrity check schedules
- Supports all restic targets (tested with: Local filesystem, AWS, Backblaze, and rest-server)
- Custom hook integration
- Partial and full restore
- Includes mysql/mariadb dump before the backup run
- Healthcheck (via https://healthchecks.io/) or email notifications

## SeaTable and Seafile Specific Extension

This container is essentially a wrapper for the well-established backup software [restic](https://restic.readthedocs.io/en/latest/), suitable for any use case.

There is one SeaTable-specific extensions: a script dumps the SeaTable big data before the backup starts. This action is deactivated by default and must be enabled with this environment variable:

- `SEATABLE_BIGDATA_DUMP=true`

This Docker container is part of the [seatable docker release github repo](https://github.com/seatable/seatable-release), but it's essentially a restic backup container capable of backup up everything **plus a mysql/mariadb dump**.

## How to use

Everything below `/data/` in the container is part of the backup. Mount all data to be backed up as a read-only volume below `/data/`. All restic targets are supported, including rest-server, S3, Backblaze, and even the host filesystem. The backup and check schedule is executed via cron inside the container.

**Important**: Avoid mounting something directly to `/data/` directory as read-only. Otherwise database dumps will not work because it creates a folder `/data/database-dumps`.
Instead mount everything in subdirectory like `/data/seatable-compose`, `/data/seafile` or `/data/anything-else`.

### Commands

You can easily execute any restic command in the Docker container. Refer to the [official restic documentation](https://restic.readthedocs.io/)] for more details. Here are some examples:

```bash
docker exec -it restic-backup restic [command]

# Examples:
docker exec -it restic-backup restic -h
docker exec -it restic-backup restic snapshots
docker exec -it restic-backup restic version
docker exec -it restic-backup restic stats
```

Additionally, there are two simple commands for backup and checking consistency. These commands are also executed according to the CRON schedule.

To manually perform a backup or check consistency, independent of the CRON, run:

```bash
docker exec -it restic-backup backup
docker exec -it restic-backup check
```

### Hooks

The Container supports the execution of the following custom hooks (if available at the container). Hooks are skipped if no scripts are found.

- /hooks/pre-backup.sh
- /hooks/post-backup.sh
- /hooks/pre-check.sh
- /hooks/post-check.sh

### Logs

By default the container returns logs to stdout. You can get the log output of the container with `docker logs restic-backup -f`.

If `LOG_TYPE` is set to `file`, the container also writes a log file to `/var/log/restic/backup.log` which is mounted as volume to `/opt/restic/logs` in the host.

## Customize the Container

The container is set up by setting environment variables and volumes.

### Environment variables

| Name                       | Description                                     | Example                                                           | Default           |
| -------------------------- | ----------------------------------------------- | ----------------------------------------------------------------- | ----------------- |
| `RESTIC_REPOSITORY`        | Restic backup target                            | `/local` or `rest:https://backup.seatable.io`                     | _required_        |
| `RESTIC_PASSWORD`          | Encryption password                             | `topsecret`                                                       | _required_        |
| `BACKUP_CRON`              | Execution schedule for the backup               | `20 2 * * *`                                                      | `20 2 * * *`      |
| `CHECK_CRON`               | Execution schedule integrity check              | `40 3 * * 6`                                                      | `40 3 * * 6`      |
| `LOG_LEVEL`                | Define log level                                | `DEBUG`, `INFO`, `WARNING` or `ERROR`.                            | `INFO`            |
| `LOG_TYPE`                 | Define the log output type                      | `stdout` or `file`                                                | `stdout`          |
| `TZ`                       | Timezone                                        | `Europe/Berlin`                                                   |                   |
| `RESTIC_TAG`               | Tag for backup                                  | `seatable`                                                        | `seatable`        |
| `RESTIC_DATA_SUBSET`       | Restic checks only a subset of data             | `1G` or `10%` or `1/10`                                           | `1G`              |
| `RESTIC_FORGET_ARGS`       | Restic Forget parameters                        | ` --prune --keep-daily 6 --keep-monthly 6`                        |                   |
| `RESTIC_JOB_ARGS`          | Restic Job execution parameters                 | ` --exclude=/data/logs --exclude-if-present .exclude_from_backup` |                   |
| `RESTIC_SKIP_INIT`         | Skip restic initialization                      | `true` or `false`                                                 | `false`           |
| `SEATABLE_DATABASE_DUMP`   | Enable mysql/mariadb database dump (DEPRECATED) | `true` or `false`                                                 | `false`           |
| `DATABASE_DUMP`            | Enable mysql/mariadb database dump              | `true` or `false`                                                 | `false`           |
| `DATABASE_HOST`            | Name of the mariadb/mysql container             | `mariadb`                                                         | `mariadb`         |
| `DATABASE_USER`            | User for connection to database                 | `root`                                                            | `root`            |
| `DATABASE_PASSWORD`        | Password for connection to database             | `topsecret`                                                       |                   |
| `DATABASE_LIST`            | List of databases to export (empyt=all)         | `dtable_db,ccnet_db,seafile_db`                                   |                   |
| `SEATABLE_BIGDATA_DUMP`    | Enable dump of big data                         | `true`or`false`                                                   | `false`           |
| `SEATABLE_BIGDATA_HOST`    | Name of the SeaTable Server container           | `seatable-server`                                                 | `seatable-server` |
| `HEALTHCHECK_URL`          | healthcheck.io server check url                 | `https://healthcheck.io/ping/a444061a`                            |                   |
| `MSMTP_ARGS`               | SMTP settings for mail notification             | `--host=x --port=587 ... cdb@seatable.io`                         |                   |
| `AWS_DEFAULT_REGION`       | Required only for S3 backend                    | `eu-west-1`                                                       |                   |
| `AWS_ACCESS_KEY_ID`        | Required only for S3 backend                    |                                                                   |                   |
| `AWS_SECRET_ACCESS_KEY`    | Required only for S3 backend                    |                                                                   |                   |
| `B2_ACCOUNT_ID`            | Required only for backblaze backend             |                                                                   |                   |
| `B2_ACCOUNT_KEY`           | Required only for backblaze backend             |                                                                   |                   |

### Mail notification

Mail notification is optional. If specified, the content of `/var/log/restic/lastrun.log` is sent via mail after each backup and data integrity check using an external SMTP. To have maximum flexibility, you have to provide a msmtp configuration file with the mail/smtp parameters on your own. Have a look at the [msmtp manpage](https://wiki.debian.org/msmtp) for further information.

Here is an example of `MSMTP_ARGS`, to specify the recipient of the notification.

```bash
# example of MSMTP_ARGS
MSMTP_ARGS="recipient@example.com"
MSMTP_ARGS="-a default recipient@example.com"
```

Here is the example of `/opt/restic/msmtprc.conf` to configure your external SMTP account.

```bash
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/restic/msmtp.log

account        brevo
host           smtp-relay.brevo.com
port           587
from           noreply@seatable.io
user           your-username
password       your-password

account default: brevo
```

## Example docker-compose

Get the latest version of the container from <https://hub.docker.com/repository/docker/seatable/restic-backup>.

```yaml
---
services:
  restic-backup:
    image: ${SEATABLE_RESTIC_BACKUP_IMAGE:-seatable/restic-backup:1.4.0}
    container_name: restic-backup
    restart: unless-stopped
    init: true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/seatable-compose:/data/seatable-compose:ro
      - /opt/seatable-server/seatable:/data/seatable-server:ro
      - /opt/restic/local:/local
      - /opt/restic/restore:/restore
      - /opt/restic/cache:/root/.cache/restic
      #- /opt/restic/hooks:/hooks:ro
      #- /opt/restic/logs:/var/log/restic
      #- /opt/restic/msmtprc.conf:/root/.msmtprc:ro
    environment:
      - RESTIC_REPOSITORY=${RESTIC_REPOSITORY:?Variable is not set or empty}
      - RESTIC_PASSWORD=${RESTIC_PASSWORD:?Variable is not set or empty}
      # - RESTIC_TAG=${SEATABLE_SERVER_HOSTNAME:-seatable}
      # - BACKUP_CRON=${BACKUP_CRON:-15 2 * * *} # Start backup always at 2:15 am.
      # - CHECK_CRON=${CHECK_CRON:-45 3 \* \* 6} # Start check every sunday at 3:45am
      # - LOG_LEVEL=${LOG_LEVEL:-INFO}
      # - LOG_TYPE=${LOG_TYPE:-stdout}
      # - TZ=${TIME_ZONE}
      # - RESTIC_DATA_SUBSET=${RESTIC_DATA_SUBSET:-1G} # Download max 1G of data from backup and check the data integrity
      # - RESTIC_FORGET_ARGS=${RESTIC_FORGET_ARGS:- --prune --keep-daily 6 --keep-weekly 4 --keep-monthly 6}
      # - RESTIC_JOB_ARGS=${RESTIC_JOB_ARGS:- --exclude=/data/seatable-server/seatable/logs --exclude=/data/seatable-server/seatable/db-data --exclude-if-present .exclude_from_backup}
      # - RESTIC_SKIP_INIT=${RESTIC_SKIP_INIT}
      # - DATABASE_DUMP=${DATABASE_DUMP:-true}
      # - DATABASE_HOST=${DATABASE_HOST:-mariadb}
      # - DATABASE_USER=${DATABASE_USER:-root}
      # - DATABASE_PASSWORD=${SEATABLE_MYSQL_ROOT_PASSWORD:?Variable is not set or empty}
      # - DATABASE_LIST=${DATABASE_LIST}
      # - SEATABLE_BIGDATA_DUMP=${SEATABLE_BIGDATA_DUMP:-true}
      # - SEATABLE_BIGDATA_HOST=${SEATABLE_BIGDATA_HOST:-seatable-server}
      # - HEALTHCHECK_URL=${HEALTHCHECK_URL}
      # - MSMTP_ARGS=${MSMTP_ARGS}
```

## How to restore

### Restore to host server

Restore files inside the Docker container to the `/restore` folder, which is mounted to the host system.

To restore files from the latest snapshot, use the following command:

```bash
docker exec -it restic-backup restic restore latest --target /restore
```

If you want to restore only a subset from an older snapshot, use this command:

```bash
# get snapshot ids
docker exec -it restic-backup restic snapshots

# get list of files in a snapshot (you will need the path to the files for partial restore)
docker exec -it restic-backup restic ls <snapshot>

# restore only config files from a specific snapshot
docker exec -it restic-backup restic restore <snapshot> --include /data/seatable-server/seatable/conf/ --target /restore
```

All commands from the [official restic documentation](https://restic.readthedocs.io/) are supported.

### Mount

`restic mount` allows you to mount a snapshot to make it accessable like a local filesystem.

However, using "FUSE" (Filesystem in Userspace) in a Docker setup can create various problems. Therefore, we've removed everything related to mounting from this container. Please avoid using it.

## Two backup targets

Sometimes you might want to backup to two different repositories. In this case it is no problem to run to backup containers in parallel. The volume configuration can be the same, but it is advised that you run the backups to different times. Therefore choose different values for `BACKUP_CRON` and `CHECK_CRON`.
