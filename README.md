# Restic Backup Docker Container (for SeaTable)

A docker container to automate restic backups of your SeaTable Server.

This container runs restic backups (and checks) in regular intervals.

- Easy setup and maintanance
- Define a schedule for backup and integrity checks
- Support for different targets (tested with: Local filesystem of the host, AWS, Backblaze and rest-server)
- Healthcheck (https://healthchecks.io/) or mail notifications possible
- Partial and full restore possible

Use with docker compose, latest yml files at seatable docker release github repo.

## How to use

Everything below `/data/` folder in the container will be part of the backup.
All restic targets are supported like rest-server, S3, backblaze and even the same filesystem of the host.
Executed via cron inside the container.

### Commands

In general every restic command can be easily executed in the docker container like these. Check the [official restic documentation](https://restic.readthedocs.io/) for more details.

```bash
docker exec -it restic-backup restic [command]

# Examples:
docker exec -it restic-backup restic -h
docker exec -it restic-backup restic snapshots
docker exec -it restic-backup restic version
docker exec -it restic-backup restic stats
```

In addition there are two easy to use command for backup and check. These are executed according the CRON schedule.
To execute a backup or the check the consistency manually, independent of the CRON, just run:

```bash
docker exec -it restic-backup backup
docker exec -it restic-backup check
```

### Hooks

Container supports the execution of the following custom hooks (if available at the container).

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

| Name                         | Description                           | Example                                                           | Default           |
| ---------------------------- | ------------------------------------- | ----------------------------------------------------------------- | ----------------- |
| `RESTIC_REPOSITORY`          | Restic backup target                  | `/local` or `rest:https://backup.seatable.io`                     | _required_        |
| `RESTIC_PASSWORD`            | Encryption password                   | `topsecret`                                                       | _required_        |
| `BACKUP_CRON`                | Execution schedule for the backup     | `20 2 * * *`                                                      | `20 2 * * *`      |
| `CHECK_CRON`                 | Execution schedule integrity check    | `40 3 * * 6`                                                      | `40 3 * * 6`      |
| `LOG_LEVEL`                  | Define log level                      | `DEBUG`, `INFO`, `WARNING` or `ERROR`.                            | `INFO`            |
| `LOG_TYPE`                   | Define the log output type            | `stdout` or `file`                                                | `stdout`          |
| `TZ`                         | Timezone                              | `Europe/Berlin`                                                   |                   |
| `RESTIC_TAG`                 | Tag for backup                        | `seatable`                                                        | `seatable`        |
| `RESTIC_DATA_SUBSET`         | Restic checks only a subset of data   | `1G` or `10%` or `1/10`                                           | `1G`              |
| `RESTIC_FORGET_ARGS`         | Restic Forget parameters              | ` --prune --keep-daily 6 --keep-monthly 6`                        | like Example      |
| `RESTIC_JOB_ARGS`            | Restic Job execution parameters       | ` --exclude=/data/logs --exclude-if-present .exclude_from_backup` | like Example      |
| `SEATABLE_DATABASE_DUMP`     | Enable SeaTable database dump         | `true` or `false`                                                 | `false`           |
| `SEATABLE_DATABASE_HOST`     | Name of the mariadb container         | `mariadb`                                                         | `mariadb`         |
| `SEATABLE_DATABASE_USER`     | User for connection to mariadb        | `root`                                                            | `root`            |
| `SEATABLE_DATABASE_PASSWORD` | Password for connection to mariadb    | `topsecret`                                                       |                   |
| `SEATABLE_BIGDATA_DUMP`      | Enable dump of big data               | `true` or `false`                                                 | `false`           |
| `SEATABLE_BIGDATA_HOST`      | Name of the SeaTable Server container | `seatable-server`                                                 | `seatable-server` |
| `HEALTHCHECK_URL`            | healthcheck.io server check url       | `https://healthcheck.io/ping/a444061a`                            |                   |
| `MAILX_ARGS`                 | SMTP settings for mail notification   | `-S smtp=smtp.example.com -S smtp-use-starttls -S ...`            |                   |
| `AWS_DEFAULT_REGION`         | Required only for S3 backend          | `eu-west-1`                                                       |                   |
| `AWS_ACCESS_KEY_ID`          | Required only for S3 backend          |                                                                   |                   |
| `AWS_SECRET_ACCESS_KEY_ID`   | Required only for S3 backend          |                                                                   |                   |
| `B2_ACCOUNT_ID`              | Required only for backblaze backend   |                                                                   |                   |
| `B2_ACCOUNT_KEY`             | Required only for backblaze backend   |                                                                   |                   |

## Example docker-compose

```yaml
---
services:
  restic-backup:
    image: ${SEATABLE_RESTIC_BACKUP_IMAGE:-seatable/restic-backup:1.1.0}
    container_name: restic-backup
    restart: unless-stopped
    init: true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/seatable-compose:/data/seatable-compose:ro
      - /opt/seatable-server/seatable:/data/seatable-server/seatable:ro
      - /opt/restic/local:/local
      - /opt/restic/restore:/restore
      - /opt/restic/cache:/root/.cache/restic
      - /opt/restic/hooks:/hooks:ro
      - /opt/restic/logs:/var/log/restic
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
      # - SEATABLE_DATABASE_DUMP=${SEATABLE_DATABASE_DUMP:-true}
      # - SEATABLE_DATABASE_HOST=${SEATABLE_DATABASE_HOST:-mariadb}
      # - SEATABLE_DATABASE_USER=${SEATABLE_DATABASE_USER:-root}
      # - SEATABLE_DATABASE_PASSWORD=${SEATABLE_MYSQL_ROOT_PASSWORD:?Variable is not set or empty}
      # - SEATABLE_BIGDATA_DUMP=${SEATABLE_BIGDATA_DUMP:-true}
      # - SEATABLE_BIGDATA_HOST=${SEATABLE_BIGDATA_HOST:-seatable-server}
      # - HEALTHCHECK_URL=${HEALTHCHECK_URL}
```

## How to restore

### Restore to host server

Restore inside the docker container to the /restore folder. This is mounted to the host system and the files can be seen there.
Use the following command to restore files from the latest snapshot.

```bash
docker exec -it restic-backup restic restore latest --target /restore
```

If you want to restore only a subset and from an old snapshot, use this command:
All commands from the [official restic documentation](https://restic.readthedocs.io/) are supported.

```bash
# get snapshot ids
docker exec -it restic-backup restic snapshots

# get list of files in a snapshot (you will need the path to the files for partial restore)
docker exec -it restic-backup restic ls <snapshot>

# restore only config files from a specific snapshot
docker exec -it restic-backup restic restore <snapshot> --include /data/seatable-server/seatable/conf/ --target /restore
```

### Mount

`restic mount` allows to mount a snapshot to make it accessable like a local filesystem. It uses "FUSE" (Filesystem in Userspace), which requires that the FUSE kernel component from the hosts system must be made accessible to the container. FUSE in a docker setup creates a lot of problems. Therefore we removed everything that is connected with mount. Please don't use it.
